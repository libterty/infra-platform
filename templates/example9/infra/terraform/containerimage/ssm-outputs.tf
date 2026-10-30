locals {
  published_strings = {
    api_repository_url = module.repository["api"].repository_url
    fn_repository_url  = module.repository["fn"].repository_url
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "containerimage"
  strings    = local.published_strings
}
