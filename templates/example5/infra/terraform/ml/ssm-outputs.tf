locals {
  published_strings = {
    model_package_group_arn  = module.registry.arn
    model_package_group_name = module.registry.name
    pipeline_name            = module.pipeline.pipeline_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "ml"
  strings    = local.published_strings
}
