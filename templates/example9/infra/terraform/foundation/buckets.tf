# Pipeline artifacts only live for one execution (design K8), so they expire after 30 days in both envs.
# The web bucket of design 8.1 is created by the web stack instead: its bucket policy must name the CloudFront
# distribution, which does not exist when foundation is applied, and s3-bucket owns the whole bucket policy.
locals {
  artifact_bucket = {
    name            = "${local.name_prefix}-artifacts-${var.expected_account_id}"
    kms_key_arn     = module.kms.key_arn
    expiration_days = 30
  }
}

module "artifact_bucket" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/s3-bucket/aws"
  version = "~> 0.6.0"

  name            = local.artifact_bucket.name
  kms_key_arn     = local.artifact_bucket.kms_key_arn
  expiration_days = local.artifact_bucket.expiration_days
}
