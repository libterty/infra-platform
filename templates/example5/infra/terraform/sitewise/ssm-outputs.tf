# The edge stack configures the KVS edge connector of each core device with its hub asset (SiteWiseAssetIdForHub).
# SSM refuses an empty value, so no cameras publishes {} (design section 7.2).
locals {
  published_strings = {
    edge_connector_asset_ids = length(var.cameras) == 0 ? jsonencode({}) : jsonencode({
      cameras = { for id, name in local.camera_name : id => module.sitewise[0].asset_ids[name] }
      hubs    = { for t, name in local.hub_name : t => module.sitewise[0].asset_ids[name] }
    })
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "sitewise"
  strings    = local.published_strings
}
