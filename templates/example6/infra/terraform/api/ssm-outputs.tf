locals {
  published_strings = {
    # Host only: the web stack uses it as the CloudFront origin domain.
    api_endpoint = trimprefix(module.api.api_endpoint, "https://")
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "api"
  strings    = local.published_strings
}
