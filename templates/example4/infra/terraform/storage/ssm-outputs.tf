locals {
  published_strings = merge(
    {
      raw_bucket_arn             = module.bucket["raw"].arn
      raw_bucket_name            = module.bucket["raw"].bucket_name
      curated_bucket_arn         = module.bucket["curated"].arn
      athena_results_bucket_arn  = module.bucket["athena_results"].arn
      athena_results_bucket_name = module.bucket["athena_results"].bucket_name
      glue_assets_bucket_arn     = module.bucket["glue_assets"].arn
      raw_database_name          = local.databases["raw"].name
      curated_database_name      = local.databases["curated"].name
      stream_arn                 = module.stream.arn
    },
    { for k, t in module.table : "table_${k}_arn" => t.arn },
  )
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "storage"
  strings    = local.published_strings
}
