locals {
  ssm_input_strings = {
    alarm_topic_arn = "foundation/alarm_topic_arn"
    db_sg_id        = "network/db_sg_id"
    cache_sg_id     = "network/cache_sg_id"
  }

  ssm_input_lists = {
    db_subnet_ids = "network/db_subnet_ids"
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
