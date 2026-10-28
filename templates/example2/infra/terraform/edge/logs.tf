# CloudFront standard logs (v2) arrive through CloudWatch Logs vended delivery. The delivery source of a distribution
# must be in us-east-1; the bucket stays in the stack's region. Cross-region delivery to S3 is not yet verified against
# a real account (design section 11). SSE-S3: log delivery cannot write with a CMK that lacks a key policy for it.
locals {
  log_bucket = {
    name            = "${local.name_prefix}-cdn-logs-${var.expected_account_id}"
    log_delivery    = ["vended_logs"]
    expiration_days = var.access_log_retention_days
  }

  cdn_logs = {
    region       = "us-east-1"
    sources      = { access = { resource_arn = module.cdn.arn, log_type = "ACCESS_LOGS" } }
    destinations = { bucket = { type = "S3", resource_arn = module.log_bucket.arn } }
    deliveries   = { access = { source = "access", destination = "bucket" } }
  }
}

module "log_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.5.0"

  name            = local.log_bucket.name
  log_delivery    = local.log_bucket.log_delivery
  expiration_days = local.log_bucket.expiration_days
}

module "cdn_logs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.3.0"

  name_prefix  = local.cdn.name
  region       = local.cdn_logs.region
  sources      = local.cdn_logs.sources
  destinations = local.cdn_logs.destinations
  deliveries   = local.cdn_logs.deliveries

  # The bucket policy is a separate resource inside s3-bucket; depending on the ARN alone would let the delivery be
  # created before CloudWatch Logs is allowed to write.
  depends_on = [module.log_bucket]
}
