locals {
  published_strings = {
    opensearch_domain_arn  = module.domain.domain_arn
    opensearch_domain_name = module.domain.domain_name
    opensearch_endpoint    = module.domain.endpoint
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "search"
  strings    = local.published_strings
}
