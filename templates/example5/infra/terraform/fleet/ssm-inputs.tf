locals {
  ssm_input_strings = {
    alarm_topic_arn           = "foundation/alarm_topic_arn"
    ca                        = "pki/ca"
    ota_bucket_arn            = "storage/ota_bucket_arn"
    role_iot_provisioning_arn = "iam-base/role_iot_provisioning_arn"
    role_iot_logging_arn      = "iam-base/role_iot_logging_arn"
    role_iot_audit_arn        = "iam-base/role_iot_audit_arn"
    role_iot_mitigation_arn   = "iam-base/role_iot_mitigation_arn"
    role_greengrass_tes_arn   = "iam-base/role_greengrass_tes_arn"
    role_ota_presign_arn      = "iam-base/role_ota_presign_arn"
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

locals {
  iot_arn_prefix = "arn:aws:iot:${var.aws_region}:${var.expected_account_id}"

  # awscc has no default_tags (design K3), so its modules get the same tags the aws provider adds.
  awscc_tags = merge(local.common_tags, { Stack = "fleet" })
}
