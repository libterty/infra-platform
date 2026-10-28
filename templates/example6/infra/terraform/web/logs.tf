# CloudFront standard logs (v2): the delivery source of a distribution must be in us-east-1; the bucket stays in the
# stack's region. Cross-region delivery to S3 is not yet verified against a real account (design section 11).
locals {
  cdn_logs = {
    region       = "us-east-1"
    sources      = { access = { resource_arn = module.cdn.arn, log_type = "ACCESS_LOGS" } }
    destinations = { bucket = { type = "S3", resource_arn = module.log_bucket.arn } }
    deliveries   = { access = { source = "access", destination = "bucket" } }
  }
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
