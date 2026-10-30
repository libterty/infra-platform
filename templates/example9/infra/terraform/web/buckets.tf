# The SPA files: SSE-S3 because the content is public anyway and CloudFront could not decrypt a CMK-encrypted object
# without a key policy change. Only this distribution may read, through its OAC; the pipeline's S3 deploy action writes.
locals {
  site_bucket = {
    # Must match iam/naming.tf: the pipeline role's S3 deploy permission is built from this name.
    name         = "${local.name_prefix}-web-${var.expected_account_id}"
    never_expire = true
  }
  # Separate from site_bucket: the distribution reads the bucket domain, so the bucket name must not wait for it.
  site_bucket_readers = [module.cdn.arn]
}

module "site_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.6.0"

  name                         = local.site_bucket.name
  never_expire                 = local.site_bucket.never_expire
  cloudfront_distribution_arns = local.site_bucket_readers
}
