locals {
  ssm_input_strings = {
    alert_topic_arn = "foundation/alert_topic_arn"
    # Not used by any resource: reading it fails the plan until audit has turned Config on, which the Security Hub
    # FSBP and CIS controls evaluate through.
    config_recorder_name = "audit/config_recorder_name"
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
