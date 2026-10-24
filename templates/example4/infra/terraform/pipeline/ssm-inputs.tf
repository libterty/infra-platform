locals {
  ssm_input_strings = {
    kms_key_arn            = "foundation/kms_key_arn"
    alarm_topic_arn        = "foundation/alarm_topic_arn"
    sg_firehose_id         = "network/sg_firehose_id"
    raw_bucket_arn         = "storage/raw_bucket_arn"
    curated_bucket_arn     = "storage/curated_bucket_arn"
    glue_assets_bucket_arn = "storage/glue_assets_bucket_arn"
    raw_database_name      = "storage/raw_database_name"
    curated_database_name  = "storage/curated_database_name"
    stream_arn             = "storage/stream_arn"
    role_firehose_arn      = "iam-base/role_firehose_arn"
    role_glue_crawler_arn  = "iam-base/role_glue_crawler_arn"
    role_glue_job_arn      = "iam-base/role_glue_job_arn"
    role_glue_events_arn   = "iam-base/role_glue_events_arn"
    opensearch_domain_arn  = "search/opensearch_domain_arn"
  }
  ssm_input_lists = {
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

locals {
  kms_key_arn            = module.in.strings["kms_key_arn"]
  raw_bucket_arn         = module.in.strings["raw_bucket_arn"]
  curated_bucket_arn     = module.in.strings["curated_bucket_arn"]
  glue_assets_bucket_arn = module.in.strings["glue_assets_bucket_arn"]

  # storage publishes the bucket ARNs; the s3:// URIs are the ARNs without the "arn:<partition>:s3:::" part.
  raw_bucket_name         = element(split(":::", local.raw_bucket_arn), 1)
  curated_bucket_name     = element(split(":::", local.curated_bucket_arn), 1)
  glue_assets_bucket_name = element(split(":::", local.glue_assets_bucket_arn), 1)
}
