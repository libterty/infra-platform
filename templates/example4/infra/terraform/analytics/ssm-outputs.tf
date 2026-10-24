locals {
  published_strings = {
    athena_workgroup_name = module.workgroup.name
    athena_workgroup_arn  = module.workgroup.arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "analytics"
  strings    = local.published_strings
}
