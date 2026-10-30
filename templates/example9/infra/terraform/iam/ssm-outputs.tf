locals {
  published_strings = {
    api_execution_role_arn  = module.role["api_execution"].arn
    api_task_role_arn       = module.role["api_task"].arn
    fn_role_arn             = module.role["fn"].arn
    api_build_role_arn      = module.role["api_build"].arn
    api_deploy_role_arn     = module.role["api_deploy"].arn
    fn_build_role_arn       = module.role["fn_build"].arn
    web_build_role_arn      = module.role["web_build"].arn
    web_invalidate_role_arn = module.role["web_invalidate"].arn
    pipeline_role_arn       = module.role["pipeline"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "iam"
  strings    = local.published_strings

  # application and pipeline must not see a role before its permissions are attached.
  depends_on = [module.policy]
}
