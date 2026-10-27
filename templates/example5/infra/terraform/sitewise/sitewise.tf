locals {
  # awscc has no default_tags (design K3).
  awscc_tags = merge(local.common_tags, { Stack = "sitewise" })

  # KVS edge connector (design section 2 item 10, K14). The awscc asset resource cannot set attribute values, so every
  # per-camera value is the default of a model of its own: one camera model per camera, one hub model per core device.
  # The hub has one ConnectedCameras-<id> hierarchy per camera model; that the connector follows several hierarchies
  # is not verified against a real account (design section 11).
  core_things = toset([for c in values(var.cameras) : c.core_thing_name])
  hub_name    = { for t in local.core_things : t => "${local.name_prefix}-hub-${t}" }
  camera_name = { for id, c in var.cameras : id => "${local.name_prefix}-cam-${id}" }

  camera_models = {
    for id, c in var.cameras : local.camera_name[id] => {
      description = "Camera ${id} of ${c.core_thing_name}"
      properties = {
        # The KVS stream of the edge stack has the same name.
        KinesisVideoStreamName            = { data_type = "STRING", type = "attribute", default_value = local.camera_name[id] }
        RTSPStreamSecretARN               = { data_type = "STRING", type = "attribute", default_value = c.rtsp_secret_arn }
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
      hierarchies = {}
    }
  }

  hub_models = {
    for t in local.core_things : local.hub_name[t] => {
      description = "KVS edge connector hub of ${t}"
      properties  = { HubName = { data_type = "STRING", type = "attribute", default_value = t } }
      hierarchies = { for id, c in var.cameras : "ConnectedCameras-${id}" => local.camera_name[id] if c.core_thing_name == t }
    }
  }

  asset_models = merge(local.hub_models, local.camera_models)

  assets = merge(
    { for t in local.core_things : local.hub_name[t] => { model = local.hub_name[t], parent = null } },
    {
      for id, c in var.cameras : local.camera_name[id] => {
        model  = local.camera_name[id]
        parent = { asset = local.hub_name[c.core_thing_name], hierarchy = "ConnectedCameras-${id}" }
      }
    },
  )

  gateways = { for k, g in var.gateways : "${local.name_prefix}-${k}" => g }
}

module "sitewise" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iotsitewise/aws"
  version = "~> 0.1.0"
  count   = length(var.cameras) + length(var.gateways) == 0 ? 0 : 1

  asset_models = local.asset_models
  assets       = local.assets
  gateways     = local.gateways
  tags         = local.awscc_tags
}
