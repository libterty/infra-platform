locals {
  ssm_input_strings = {
    alarm_topic_arn                = "foundation/alarm_topic_arn"
    signing_private_key_secret_arn = "foundation/signing_private_key_secret_arn"
    signing_public_key_secret_arn  = "foundation/signing_public_key_secret_arn"
    agent_runtimes                 = "containerimage/agent_runtimes"
    ecr_repository_urls            = "containerimage/ecr_repository_urls"
    vpc_id                         = "network/vpc_id"
    alb_sg_id                      = "network/alb_sg_id"
    app_sg_id                      = "network/app_sg_id"
    agent_sg_id                    = "network/agent_sg_id"
    bastion_sg_id                  = "network/bastion_sg_id"
    db_proxy_endpoint              = "database/db_proxy_endpoint"
    db_secret_arn                  = "database/db_secret_arn"
    rate_limit_redis_endpoint      = "database/rate_limit_redis_endpoint"
    stream_redis_endpoint          = "database/stream_redis_endpoint"
    ecs_execution_role_arn         = "iam/ecs_execution_role_arn"
    api_task_role_arn              = "iam/api_task_role_arn"
    worker_task_role_arn           = "iam/worker_task_role_arn"
    import_extract_role_arn        = "iam/import_extract_role_arn"
    import_load_role_arn           = "iam/import_load_role_arn"
    agent_runtime_role_arn         = "iam/agent_runtime_role_arn"
  }

  ssm_input_lists = {
    services          = "containerimage/services"
    public_subnet_ids = "network/public_subnet_ids"
    app_subnet_ids    = "network/app_subnet_ids"
    agent_subnet_ids  = "network/agent_subnet_ids"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
