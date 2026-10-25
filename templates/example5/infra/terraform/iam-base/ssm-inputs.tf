locals {
  ssm_input_strings = {
    kms_key_arn                     = "foundation/kms_key_arn"
    alarm_topic_arn                 = "foundation/alarm_topic_arn"
    sg_sagemaker_id                 = "network/sg_sagemaker_id"
    stream_arn                      = "storage/stream_arn"
    rule_errors_queue_arn           = "storage/rule_errors_queue_arn"
    greengrass_artifacts_bucket_arn = "storage/greengrass_artifacts_bucket_arn"
    ota_bucket_arn                  = "storage/ota_bucket_arn"
    ml_bucket_arn                   = "storage/ml_bucket_arn"
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
