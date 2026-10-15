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
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
