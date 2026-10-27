# Account and region level: a second project in the same account sets account_settings = null (design K9).
locals {
  account_settings = var.account_settings == null ? null : {
    indexing = {
      thing_indexing_mode              = "REGISTRY"
      thing_connectivity_indexing_mode = "STATUS"
      thing_group_indexing_mode        = "ON"
    }
    logging = {
      role_arn          = module.in.strings["role_iot_logging_arn"]
      default_log_level = var.account_settings.log_level
    }
    event_configurations = {
      THING                  = true
      THING_GROUP_MEMBERSHIP = true
      JOB                    = true
      JOB_EXECUTION          = true
      CERTIFICATE            = true
    }
  }
}

module "account_settings" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iot-account-settings/aws"
  version = "~> 0.1.0"
  count   = var.account_settings == null ? 0 : 1

  indexing             = local.account_settings.indexing
  logging              = local.account_settings.logging
  event_configurations = local.account_settings.event_configurations
}
