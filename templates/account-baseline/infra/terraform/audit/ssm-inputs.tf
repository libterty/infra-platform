locals {
  ssm_input_strings = {
    kms_key_arn         = "foundation/kms_key_arn"
    trail_bucket_name   = "foundation/trail_bucket_name"
    config_bucket_name  = "foundation/config_bucket_name"
    alert_topic_arn     = "foundation/alert_topic_arn"
    config_role_arn     = "iam/config_role_arn"
    trail_logs_role_arn = "iam/trail_logs_role_arn"
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
