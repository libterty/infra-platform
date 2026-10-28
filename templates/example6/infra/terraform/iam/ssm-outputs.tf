locals {
  published_strings = {
    api_role_arn = module.api_role.arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam"
  strings    = local.published_strings

  # The api stack must not see the role before its permissions are attached.
  depends_on = [module.api_policy]
}
