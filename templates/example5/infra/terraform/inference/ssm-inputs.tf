locals {
  ssm_input_strings = {
    kms_key_arn                 = "foundation/kms_key_arn"
    alarm_topic_arn             = "foundation/alarm_topic_arn"
    sg_sagemaker_id             = "network/sg_sagemaker_id"
    ml_bucket_name              = "storage/ml_bucket_name"
    role_sagemaker_endpoint_arn = "iam-base/role_sagemaker_endpoint_arn"
    model_package_group_name    = "ml/model_package_group_name"
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
