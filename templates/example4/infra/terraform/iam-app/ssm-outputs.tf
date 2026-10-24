locals {
  published_strings = {
    role_quicksight_athena_arn = module.quicksight_athena_role.arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-app"
  strings    = local.published_strings
}
