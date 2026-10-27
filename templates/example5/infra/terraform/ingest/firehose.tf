locals {
  # Time prefix under raw/, failures under errors/: the two prefixes iam-app lets the firehose role write.
  firehose_s3 = {
    name              = "${local.name_prefix}-to-raw"
    role_arn          = module.in.strings["role_firehose_arn"]
    source_stream_arn = local.stream_arn
    s3 = {
      bucket_arn          = local.telemetry_bucket_arn
      prefix              = "raw/!{timestamp:yyyy/MM/dd/HH}/"
      error_output_prefix = "errors/s3/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/HH}/"
      buffering_size      = 64
      buffering_interval  = 900
      compression         = "GZIP"
    }
  }

  # The S3 part is only the backup of failed documents, so it stays under errors/. The index matches the patterns of
  # search-config (<name_prefix>-events*).
  firehose_opensearch = {
    name              = "${local.name_prefix}-to-search"
    role_arn          = module.in.strings["role_firehose_arn"]
    source_stream_arn = local.stream_arn
    opensearch = {
      domain_arn         = module.in.strings["opensearch_domain_arn"]
      index_name         = "${local.name_prefix}-events"
      subnet_ids         = toset(module.in.lists["subnet_ids_data"])
      security_group_ids = toset([module.in.strings["sg_firehose_id"]])
    }
    s3 = {
      bucket_arn          = local.telemetry_bucket_arn
      prefix              = "errors/opensearch/!{timestamp:yyyy/MM/dd}/"
      error_output_prefix = "errors/opensearch-processing/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
      buffering_size      = 5
      buffering_interval  = 60
      compression         = "GZIP"
    }
  }
}

module "firehose_s3" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/firehose-stream/aws"
  version = "~> 0.1.0"

  name              = local.firehose_s3.name
  role_arn          = local.firehose_s3.role_arn
  kms_key_arn       = local.kms_key_arn
  source_stream_arn = local.firehose_s3.source_stream_arn
  s3                = local.firehose_s3.s3
}

module "firehose_opensearch" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/firehose-stream/aws"
  version = "~> 0.1.0"

  name              = local.firehose_opensearch.name
  role_arn          = local.firehose_opensearch.role_arn
  kms_key_arn       = local.kms_key_arn
  source_stream_arn = local.firehose_opensearch.source_stream_arn
  s3                = local.firehose_opensearch.s3
  opensearch        = local.firehose_opensearch.opensearch
}
