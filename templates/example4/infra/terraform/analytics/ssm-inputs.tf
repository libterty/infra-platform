locals {
  ssm_input_strings = {
    kms_key_arn                = "foundation/kms_key_arn"
    athena_results_bucket_name = "storage/athena_results_bucket_name"
    curated_database_name      = "storage/curated_database_name"
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
