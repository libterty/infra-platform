locals {
  published_strings = {
    cluster_name          = module.cluster.cluster_name
    api_service_name      = module.api.service_name
    worker_service_name   = module.worker.service_name
    api_log_group_name    = module.api.log_group_name
    worker_log_group_name = module.worker.log_group_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "application"
  strings    = local.published_strings
}
