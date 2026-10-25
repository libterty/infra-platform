locals {
  ssm_input_strings = {
    kms_key_arn                 = "foundation/kms_key_arn"
    ml_bucket_name              = "storage/ml_bucket_name"
    model_approved_queue_arn    = "storage/model_approved_queue_arn"
    role_sagemaker_pipeline_arn = "iam-base/role_sagemaker_pipeline_arn"
    role_scheduler_arn          = "iam-base/role_scheduler_arn"
  }
  ssm_input_lists = {}
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
