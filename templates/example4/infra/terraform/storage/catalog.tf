locals {
  # Athena and Redshift Spectrum only accept lowercase letters, digits and underscores in database names.
  database_prefix = replace(local.name_prefix, "-", "_")

  databases = {
    raw     = { name = "${local.database_prefix}_raw", description = "原始資料層：Firehose 寫入 raw bucket 的 JSON。", location_uri = "s3://${local.buckets["raw"].name}/raw/" }
    curated = { name = "${local.database_prefix}_curated", description = "整理後資料層：Glue job 轉成 Parquet 的結果。", location_uri = "s3://${local.buckets["curated"].name}/" }
  }
}

module "catalog" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/glue-catalog/aws"
  version = "~> 0.1.0"

  databases = { for d in values(local.databases) : d.name => { description = d.description, location_uri = d.location_uri } }
}
