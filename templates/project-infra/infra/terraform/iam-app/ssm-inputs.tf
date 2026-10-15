locals {
  ssm_input_strings = {
    kms_key_arn        = "foundation/kms_key_arn"
    data_access        = "network/data_access"
    role_rds_proxy_arn = "iam-base/role_rds_proxy_arn"
    database           = "data/database"
  }
  ssm_input_lists = {
    services = "containerimage/services"
  }
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
