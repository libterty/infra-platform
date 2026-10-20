locals {
  ssm_input_strings = {
    api_target_group_arn = "loadbalancer/api_target_group_arn"
    agent_runtime_arns   = "agent/agent_runtime_arns"
    agent_memory_id      = "agent/agent_memory_id"
  }

  shared_input_strings = {
    vpc_id                         = "infra/vpc_id"
    app_sg_id                      = "infra/app_sg_id"
    ecs_execution_role_arn         = "infra/ecs_execution_role_arn"
    api_task_role_arn              = "infra/api_task_role_arn"
    worker_task_role_arn           = "infra/worker_task_role_arn"
    signing_private_key_secret_arn = "infra/signing_private_key_secret_arn"
    signing_public_key_secret_arn  = "infra/signing_public_key_secret_arn"
    db_proxy_endpoint              = "infra/db_proxy_endpoint"
    db_secret_arn                  = "infra/db_secret_arn"
    rate_limit_redis_endpoint      = "infra/rate_limit_redis_endpoint"
    stream_redis_endpoint          = "infra/stream_redis_endpoint"
    ecr_repository_urls            = "infra/ecr_repository_urls"
    alarm_topic_arn                = "infra/alarm_topic_arn"
  }

  shared_input_lists = {
    app_subnet_ids = "infra/app_subnet_ids"
    services       = "infra/services"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
  lists      = local.shared_input_lists
}
