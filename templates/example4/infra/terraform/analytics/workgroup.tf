locals {
  kms_key_arn         = module.in.strings["kms_key_arn"]
  results_bucket_name = module.in.strings["athena_results_bucket_name"]
  curated_database    = module.in.strings["curated_database_name"]

  # Design section 7.5: the same limit in dev and sit. A query that would scan more than 10 GiB is cancelled.
  bytes_scanned_cutoff_per_query = 10737418240

  # Example only: replace or add queries for your own tables. The database comes from storage.
  named_queries = {
    list_curated_tables = {
      database    = local.curated_database
      query       = "SHOW TABLES"
      description = "列出 curated database 裡的所有 table，確認 Glue job 與 catalog 已更新。"
    }
  }
}

module "workgroup" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/athena-workgroup/aws"
  version = "~> 0.1.0"

  name                           = "${local.name_prefix}-analytics"
  results_bucket_name            = local.results_bucket_name
  kms_key_arn                    = local.kms_key_arn
  bytes_scanned_cutoff_per_query = local.bytes_scanned_cutoff_per_query
  named_queries                  = local.named_queries
}
