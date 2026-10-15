locals {
  ssm_input_strings = {
    flow_log_bucket_arn = "foundation/flow_log_bucket_arn"
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
