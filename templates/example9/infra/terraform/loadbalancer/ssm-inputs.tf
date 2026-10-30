locals {
  ssm_input_strings = {
    vpc_id          = "network/vpc_id"
    vpc_cidr        = "network/vpc_cidr"
    alert_topic_arn = "foundation/alert_topic_arn"
  }
  ssm_input_lists = {
    app_subnet_ids = "network/app_subnet_ids"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
