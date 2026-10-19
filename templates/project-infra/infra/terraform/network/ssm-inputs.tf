locals {
  ssm_input_strings = {
    flow_log_bucket_arn = "foundation/flow_log_bucket_arn"
    # JSON array of Runtime names; "[]" when containerimage has no Runtime.
    agent_runtimes = "containerimage/agent_runtimes"
  }
  ssm_input_lists = {
    services = "containerimage/services"
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
