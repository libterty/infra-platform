terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.107, < 2.0"
    }
  }
}

provider "awscc" {
  region = "ap-northeast-1"
}

# The hub and camera models follow the structure the KVS edge connector expects (see the README).
module "sitewise" {
  source = "../.."

  asset_models = {
    alpha-dev-kvs-camera = {
      description = "Camera Device for EdgeConnectorForKVS"
      properties = {
        KinesisVideoStreamName            = { data_type = "STRING", type = "attribute", default_value = "alpha-dev-cam-01" }
        RTSPStreamSecretARN               = { data_type = "STRING", type = "attribute", default_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-cam-01-rtsp-AbCdEf" }
        LocalDataRetentionPeriodInMinutes = { data_type = "INTEGER", type = "attribute", default_value = "60" }
        LiveStreamingStartTime            = { data_type = "STRING", type = "attribute", default_value = "-" }
        LiveStreamingDurationInMinutes    = { data_type = "INTEGER", type = "attribute", default_value = "0" }
        CaptureStartTime                  = { data_type = "STRING", type = "attribute", default_value = "-" }
        CaptureDurationInMinutes          = { data_type = "INTEGER", type = "attribute", default_value = "0" }
        VideoUploadRequest                = { data_type = "STRING", type = "measurement" }
        VideoUploadedTimeRange            = { data_type = "DOUBLE", type = "measurement" }
        VideoRecordedTimeRange            = { data_type = "DOUBLE", type = "measurement" }
        CachedVideoAgeOutOnEdge           = { data_type = "DOUBLE", type = "measurement" }
      }
    }
    alpha-dev-kvs-hub = {
      description = "Hub Device for EdgeConnectorForKVS"
      properties = {
        HubName = { data_type = "STRING", type = "attribute", default_value = "alpha-dev-core-01" }
      }
      hierarchies = {
        ConnectedCameras = "alpha-dev-kvs-camera"
      }
    }
  }

  assets = {
    alpha-dev-hub-01 = { model = "alpha-dev-kvs-hub" }
    alpha-dev-cam-01 = {
      model  = "alpha-dev-kvs-camera"
      parent = { asset = "alpha-dev-hub-01", hierarchy = "ConnectedCameras" }
    }
  }

  gateways = {
    alpha-dev-gateway-01 = { core_device_thing_name = "alpha-dev-core-01" }
  }

  tags = {
    Project     = "alpha"
    Environment = "dev"
  }
}

output "asset_ids" {
  value = module.sitewise.asset_ids
}
