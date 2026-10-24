locals {
  kms_key_arn = module.in.strings["kms_key_arn"]

  # Design section 6. Every bucket is SSE-KMS with the shared key. Only raw sends S3 events to EventBridge: the Glue
  # workflow of the pipeline stack starts from them (design D14). Every field is set for every bucket so the map
  # keeps one type; null and [] mean "not used".
  buckets = {
    raw = {
      name            = "${local.name_prefix}-raw-${var.expected_account_id}"
      expiration_days = 365
      never_expire    = false
      transitions     = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 90, storage_class = "GLACIER_IR" }]
      versioning      = null
      eventbridge     = true
    }
    curated = {
      name            = "${local.name_prefix}-curated-${var.expected_account_id}"
      expiration_days = null
      never_expire    = true
      transitions     = []
      versioning      = { noncurrent_expiration_days = 30 }
      eventbridge     = false
    }
    athena_results = {
      name            = "${local.name_prefix}-athena-results-${var.expected_account_id}"
      expiration_days = 30
      never_expire    = false
      transitions     = []
      versioning      = null
      eventbridge     = false
    }
    glue_assets = {
      name            = "${local.name_prefix}-glue-assets-${var.expected_account_id}"
      expiration_days = 90
      never_expire    = false
      transitions     = []
      versioning      = { noncurrent_expiration_days = 30 }
      eventbridge     = false
    }
  }
}

module "bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/s3-bucket/aws"
  version  = "~> 0.4.0"
  for_each = local.buckets

  name            = each.value.name
  kms_key_arn     = local.kms_key_arn
  expiration_days = each.value.expiration_days
  never_expire    = each.value.never_expire
  transitions     = each.value.transitions
  versioning      = each.value.versioning
  eventbridge     = each.value.eventbridge
}
