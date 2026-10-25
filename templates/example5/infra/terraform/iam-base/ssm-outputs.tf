locals {
  published_strings = {
    role_iot_rule_arn           = module.role["iot_rule"].arn
    role_iot_provisioning_arn   = module.role["iot_provisioning"].arn
    role_iot_logging_arn        = module.role["iot_logging"].arn
    role_iot_audit_arn          = module.role["iot_audit"].arn
    role_iot_mitigation_arn     = module.role["iot_mitigation"].arn
    role_greengrass_tes_arn     = module.role["greengrass_tes"].arn
    role_ota_presign_arn        = module.role["ota_presign"].arn
    role_firehose_arn           = module.role["firehose"].arn
    role_firehose_name          = module.role["firehose"].name
    role_sagemaker_pipeline_arn = module.role["sagemaker_pipeline"].arn
    role_sagemaker_endpoint_arn = module.role["sagemaker_endpoint"].arn
    role_scheduler_arn          = module.role["scheduler"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-base"
  strings    = local.published_strings
}
