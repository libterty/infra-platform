locals {
  published_strings = {
    config_role_arn     = module.role["config"].arn
    backup_role_arn     = module.role["backup"].arn
    trail_logs_role_arn = module.role["trail_logs"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam"
  strings    = local.published_strings

  # audit and backup must not see a role before its permissions are attached.
  depends_on = [module.policy]
}
