locals {
  ssm_input_strings = {
    alarm_topic_arn     = "foundation/alarm_topic_arn"
    alb_log_bucket_name = "foundation/alb_log_bucket_name"
    sg_alb_id           = "network/sg_alb_id"
    alb_https           = "network/alb_https"
  }
  ssm_input_lists = {
    subnet_ids_public = "network/subnet_ids_public"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
