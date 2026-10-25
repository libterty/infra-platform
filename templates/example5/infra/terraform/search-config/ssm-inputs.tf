locals {
  ssm_input_strings = {
    opensearch_master_secret_arn = "foundation/opensearch_master_secret_arn"
    opensearch_endpoint          = "search/opensearch_endpoint"
    role_firehose_arn            = "iam-base/role_firehose_arn"
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
