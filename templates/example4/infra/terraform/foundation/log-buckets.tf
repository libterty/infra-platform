# Always created: an empty bucket costs nothing, and network decides in tfvars whether to send flow logs to it,
# so the SSM key always exists. SSE-KMS with the shared key; the key policy in kms.tf allows log delivery.
locals {
  flow_log_bucket = {
    name            = "${local.name_prefix}-flow-logs-${var.expected_account_id}"
    log_delivery    = toset(["vpc_flow_logs"])
    kms_key_arn     = module.kms.key_arn
    expiration_days = 90
  }
}

module "flow_log_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.4.0"

  name            = local.flow_log_bucket.name
  log_delivery    = local.flow_log_bucket.log_delivery
  kms_key_arn     = local.flow_log_bucket.kms_key_arn
  expiration_days = local.flow_log_bucket.expiration_days
}
