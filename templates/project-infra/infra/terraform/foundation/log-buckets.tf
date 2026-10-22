# Both buckets are always created: an empty bucket costs nothing, and downstream stacks decide in tfvars
# whether to use them, so the SSM keys always exist.
# The ALB access log bucket receives vended log delivery (loadbalancer wires it up with log-delivery).
locals {
  log_buckets = {
    flow_log = {
      name            = "${local.name_prefix}-flow-logs-${var.expected_account_id}"
      log_delivery    = ["vpc_flow_logs"]
      kms_key_arn     = null
      expiration_days = 90
    }
    alb_log = {
      name            = "${local.name_prefix}-alb-logs-${var.expected_account_id}"
      log_delivery    = ["vended_logs"]
      kms_key_arn     = null
      expiration_days = 90
    }
  }
}

module "log_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/s3-bucket/aws"
  version  = "~> 0.3.0"
  for_each = local.log_buckets

  name            = each.value.name
  log_delivery    = each.value.log_delivery
  kms_key_arn     = each.value.kms_key_arn
  expiration_days = each.value.expiration_days
}
