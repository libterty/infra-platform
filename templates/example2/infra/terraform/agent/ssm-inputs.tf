locals {
  shared_input_strings = {
    agent_sg_id            = "infra/agent_sg_id"
    agent_runtime_role_arn = "infra/agent_runtime_role_arn"
    agent_runtimes         = "infra/agent_runtimes"
    ecr_repository_urls    = "infra/ecr_repository_urls"
    db_proxy_endpoint      = "infra/db_proxy_endpoint"
    db_secret_arn          = "infra/db_secret_arn"
    db_name                = "infra/db_name"
  }

  shared_input_lists = {
    agent_subnet_ids = "infra/agent_subnet_ids"
  }
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
  lists      = local.shared_input_lists
}
