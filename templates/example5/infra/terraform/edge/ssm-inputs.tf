locals {
  ssm_input_strings = {
    kms_key_arn                      = "foundation/kms_key_arn"
    greengrass_artifacts_bucket_name = "storage/greengrass_artifacts_bucket_name"
    thing_group_fleet_arn            = "fleet/thing_group_fleet_arn"
    thing_group_core_arn             = "fleet/thing_group_core_arn"
    edge_connector_asset_ids         = "sitewise/edge_connector_asset_ids"
  }
  ssm_input_lists = {}
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

locals {
  # awscc has no default_tags (design K3).
  awscc_tags = merge(local.common_tags, { Stack = "edge" })
}
