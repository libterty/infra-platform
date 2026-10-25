locals {
  kms_key_arn = module.in.strings["kms_key_arn"]

  # Design section 7.1. Every bucket is SSE-KMS with the shared key. Telemetry tiers down like the raw bucket of
  # example4; the artifact buckets hold what devices and endpoints run, so they never expire and keep old versions.
  # Every field is set for every bucket so the map keeps one type; null and [] mean "not used".
  artifact_bucket = {
    expiration_days = null
    never_expire    = true
    transitions     = []
    versioning      = { noncurrent_expiration_days = 30 }
  }

  buckets = {
    telemetry = {
      name            = "${local.name_prefix}-telemetry-${var.expected_account_id}"
      expiration_days = 365
      never_expire    = false
      transitions     = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 90, storage_class = "GLACIER_IR" }]
      versioning      = null
    }
    # Greengrass component artifacts under artifacts/<component>/<version>/, uploaded by CI (design K10).
    greengrass_artifacts = merge(local.artifact_bucket, { name = "${local.name_prefix}-greengrass-artifacts-${var.expected_account_id}" })
    # Signed firmware for IoT Jobs under signed/ (design K17).
    ota = merge(local.artifact_bucket, { name = "${local.name_prefix}-ota-artifacts-${var.expected_account_id}" })
    # Training data, pipeline output and models (models/) of SageMaker.
    ml = merge(local.artifact_bucket, { name = "${local.name_prefix}-ml-artifacts-${var.expected_account_id}" })
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
}
