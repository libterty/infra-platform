locals {
  # For the pipeline stack: the api-deploy project and the fn Deploy action find their targets with these.
  published_strings = {
    cluster_name     = module.cluster.cluster_name
    api_service_name = module.api.service_name
    api_task_family  = module.api.task_definition_family
    fn_function_name = module.fn.function_name
    fn_alias_name    = module.fn.alias_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "application"
  strings    = local.published_strings
}
