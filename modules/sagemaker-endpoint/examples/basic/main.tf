terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "detector" {
  source = "../.."

  name               = "alpha-dev-detector"
  model_package_arn  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector/3"
  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-endpoint"
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  variant = {
    instance = { instance_type = "ml.m5.large", initial_instance_count = 2 }
  }

  vpc = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
    security_group_ids = ["sg-0aaaaaaaaaaaaaaa1"]
  }

  deployment = {
    blue_green = {
      traffic     = "CANARY"
      canary_size = { type = "CAPACITY_PERCENT", value = 10 }
    }
    rollback_alarm_names = ["alpha-dev-detector-5xx"]
  }

  data_capture = {
    destination_s3_uri  = "s3://alpha-dev-ml-artifacts/capture/"
    sampling_percentage = 20
  }

  tags = {
    Project = "alpha"
  }
}

module "detector_serverless" {
  source = "../.."

  name               = "alpha-dev-detector-sl"
  model_package_arn  = "arn:aws:sagemaker:ap-northeast-1:111111111111:model-package/alpha-dev-detector/3"
  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-endpoint"
  kms_key_arn        = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  variant = {
    serverless = { memory_size_in_mb = 2048, max_concurrency = 5 }
  }

  enable_network_isolation = false
}

output "endpoint_name" {
  value = module.detector.endpoint_name
}
