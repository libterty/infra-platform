locals {
  ssm_input_strings = {
    kms_key_arn           = "foundation/kms_key_arn"
    alarm_topic_arn       = "foundation/alarm_topic_arn"
    sg_firehose_id        = "network/sg_firehose_id"
    telemetry_bucket_arn  = "storage/telemetry_bucket_arn"
    stream_arn            = "storage/stream_arn"
    rule_errors_queue_url = "storage/rule_errors_queue_url"
    role_iot_rule_arn     = "iam-base/role_iot_rule_arn"
    role_firehose_arn     = "iam-base/role_firehose_arn"
    opensearch_domain_arn = "search/opensearch_domain_arn"
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
  kms_key_arn          = module.in.strings["kms_key_arn"]
  telemetry_bucket_arn = module.in.strings["telemetry_bucket_arn"]
  stream_arn           = module.in.strings["stream_arn"]
}
