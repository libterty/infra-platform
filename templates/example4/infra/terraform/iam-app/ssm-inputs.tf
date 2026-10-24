locals {
  ssm_input_strings = {
    kms_key_arn               = "foundation/kms_key_arn"
    sg_firehose_id            = "network/sg_firehose_id"
    raw_bucket_arn            = "storage/raw_bucket_arn"
    curated_bucket_arn        = "storage/curated_bucket_arn"
    athena_results_bucket_arn = "storage/athena_results_bucket_arn"
    curated_database_name     = "storage/curated_database_name"
    stream_arn                = "storage/stream_arn"
    role_firehose_arn         = "iam-base/role_firehose_arn"
    opensearch_domain_arn     = "search/opensearch_domain_arn"
    athena_workgroup_arn      = "analytics/athena_workgroup_arn"
  }
  ssm_input_lists = {
    subnet_ids_app  = "network/subnet_ids_app"
    subnet_ids_data = "network/subnet_ids_data"
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
