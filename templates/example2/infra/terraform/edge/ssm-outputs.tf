locals {
  # For an optional CloudFront alarm in postdeploy and for cache invalidations.
  published_strings = {
    distribution_id = module.cdn.distribution_id
    domain_name     = module.cdn.domain_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "edge"
  strings    = local.published_strings
}
