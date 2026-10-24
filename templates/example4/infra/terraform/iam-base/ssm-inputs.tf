locals {
  ssm_input_strings = {
    kms_key_arn            = "foundation/kms_key_arn"
    sg_quicksight_id       = "network/sg_quicksight_id"
    raw_bucket_arn         = "storage/raw_bucket_arn"
    curated_bucket_arn     = "storage/curated_bucket_arn"
    glue_assets_bucket_arn = "storage/glue_assets_bucket_arn"
    raw_database_name      = "storage/raw_database_name"
    curated_database_name  = "storage/curated_database_name"
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
