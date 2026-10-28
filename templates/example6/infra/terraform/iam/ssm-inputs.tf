locals {
  ssm_input_strings = {
    kms_key_arn              = "foundation/kms_key_arn"
    api_secret_arn           = "foundation/api_secret_arn"
    origin_verify_secret_arn = "foundation/origin_verify_secret_arn"
    table_arn                = "data/table_arn"
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
