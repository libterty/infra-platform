locals {
  # For the pipeline that uploads the SPA and invalidates the cache.
  published_strings = {
    site_bucket_name = module.site_bucket.bucket_name
    distribution_id  = module.cdn.distribution_id
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "web"
  strings    = local.published_strings
}
