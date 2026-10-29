# Audit evidence (design 4.1): versioning on, 365 days in every env, never force-destroyed.
# Names are <project>-<env>-<purpose>-<account>, so they stay globally unique across accounts.
locals {
  log_buckets = {
    trail = {
      name         = "${local.name_prefix}-trail-${var.expected_account_id}"
      log_delivery = ["cloudtrail"]
    }
    config = {
      name         = "${local.name_prefix}-config-${var.expected_account_id}"
      log_delivery = ["config"]
    }
  }

  log_bucket_settings = {
    kms_key_arn     = module.kms.key_arn
    expiration_days = 365
    versioning      = { noncurrent_expiration_days = 365 }
    force_destroy   = false
  }
}

module "log_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/s3-bucket/aws"
  version  = "~> 0.6.0"
  for_each = local.log_buckets

  name            = each.value.name
  log_delivery    = each.value.log_delivery
  kms_key_arn     = local.log_bucket_settings.kms_key_arn
  expiration_days = local.log_bucket_settings.expiration_days
  versioning      = local.log_bucket_settings.versioning
  force_destroy   = local.log_bucket_settings.force_destroy
}
