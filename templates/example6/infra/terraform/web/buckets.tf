# The SPA files: SSE-S3 because the content is public anyway and CloudFront could not decrypt a CMK-encrypted object
# without a key policy change (design 5.8). Only this distribution may read, through its OAC.
locals {
  site_bucket = {
    name         = "${local.name_prefix}-web-${var.expected_account_id}"
    never_expire = true
  }
  # Separate from site_bucket: the distribution reads the bucket domain, so the bucket name must not wait for it.
  site_bucket_readers = [module.cdn.arn]

  # CloudFront standard logs (v2) arrive through CloudWatch Logs vended delivery. SSE-S3: a CMK would need a key policy
  # for delivery.logs.amazonaws.com, which the shared key does not have.
  log_bucket = {
    name            = "${local.name_prefix}-cdn-logs-${var.expected_account_id}"
    log_delivery    = ["vended_logs"]
    expiration_days = var.log_retention_days
  }
}

module "site_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.5.0"

  name                         = local.site_bucket.name
  never_expire                 = local.site_bucket.never_expire
  cloudfront_distribution_arns = local.site_bucket_readers
}

module "log_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.5.0"

  name            = local.log_bucket.name
  log_delivery    = local.log_bucket.log_delivery
  expiration_days = local.log_bucket.expiration_days
}
