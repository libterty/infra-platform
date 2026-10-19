locals {
  ssm_input_strings = {
    kms_key_arn             = "foundation/kms_key_arn"
    alarm_topic_arn         = "foundation/alarm_topic_arn"
    sg_db_id                = "network/sg_db_id"
    sg_db_proxy_id          = "network/sg_db_proxy_id"
    db_proxy                = "network/db_proxy"
    role_rds_proxy_arn      = "iam-base/role_rds_proxy_arn"
    role_rds_monitoring_arn = "iam-base/role_rds_monitoring_arn"
  }
  ssm_input_lists = {
    subnet_ids_data = "network/subnet_ids_data"
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
