locals {
  published_strings = {
    ecs_execution_role_arn  = module.role["ecs_execution"].arn
    api_task_role_arn       = module.role["api_task"].arn
    worker_task_role_arn    = module.role["worker_task"].arn
    import_extract_role_arn = module.role["import_extract"].arn
    import_load_role_arn    = module.role["import_load"].arn
    agent_runtime_role_arn  = module.role["agent_runtime"].arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "iam"
  strings    = local.published_strings
}
