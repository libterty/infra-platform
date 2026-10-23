# Tree B is a verbatim copy of the tree A keys that the late stacks read. Keys no late stack reads are left out,
# so this list is also the contract for an env whose tree B is published externally (infra/README.md).
locals {
  published_strings = {
    alarm_topic_arn                = module.in.strings["alarm_topic_arn"]
    signing_private_key_secret_arn = module.in.strings["signing_private_key_secret_arn"]
    signing_public_key_secret_arn  = module.in.strings["signing_public_key_secret_arn"]
    agent_runtimes                 = module.in.strings["agent_runtimes"]
    ecr_repository_urls            = module.in.strings["ecr_repository_urls"]
    vpc_id                         = module.in.strings["vpc_id"]
    alb_sg_id                      = module.in.strings["alb_sg_id"]
    app_sg_id                      = module.in.strings["app_sg_id"]
    agent_sg_id                    = module.in.strings["agent_sg_id"]
    bastion_sg_id                  = module.in.strings["bastion_sg_id"]
    eks_api_sg_id                  = module.in.strings["eks_api_sg_id"]
    db_proxy_endpoint              = module.in.strings["db_proxy_endpoint"]
    db_secret_arn                  = module.in.strings["db_secret_arn"]
    rate_limit_redis_endpoint      = module.in.strings["rate_limit_redis_endpoint"]
    stream_redis_endpoint          = module.in.strings["stream_redis_endpoint"]
    db_name                        = module.in.strings["db_name"]
    stream_shard_count             = module.in.strings["stream_shard_count"]
    ecs_execution_role_arn         = module.in.strings["ecs_execution_role_arn"]
    api_task_role_arn              = module.in.strings["api_task_role_arn"]
    worker_task_role_arn           = module.in.strings["worker_task_role_arn"]
    import_extract_role_arn        = module.in.strings["import_extract_role_arn"]
    import_load_role_arn           = module.in.strings["import_load_role_arn"]
    agent_runtime_role_arn         = module.in.strings["agent_runtime_role_arn"]
    # Read by eks-cluster (design v4 §8.1).
    eks_cluster_role_arn      = module.in.strings["eks_cluster_role_arn"]
    eks_node_role_arn         = module.in.strings["eks_node_role_arn"]
    api_pod_role_arn          = module.in.strings["api_pod_role_arn"]
    worker_pod_role_arn       = module.in.strings["worker_pod_role_arn"]
    lb_controller_role_arn    = module.in.strings["lb_controller_role_arn"]
    keda_role_arn             = module.in.strings["keda_role_arn"]
    cloudwatch_agent_role_arn = module.in.strings["cloudwatch_agent_role_arn"]
    # Read by eks-addons: the node security group of the NodeClasses.
    node_sg_id = module.in.strings["node_sg_id"]
  }

  published_lists = {
    services          = module.in.lists["services"]
    public_subnet_ids = module.in.lists["public_subnet_ids"]
    app_subnet_ids    = module.in.lists["app_subnet_ids"]
    agent_subnet_ids  = module.in.lists["agent_subnet_ids"]
    # Read by eks-addons: the control-plane ENIs and the interface endpoints sit in these subnets.
    app_subnet_cidrs = module.in.lists["app_subnet_cidrs"]
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  stack      = "infra"
  strings    = local.published_strings
  lists      = local.published_lists

  # The guards report the key name; without this the module's own validation would fail first with a generic message.
  depends_on = [terraform_data.values_not_empty, terraform_data.subnets_span_two_azs, terraform_data.json_values_decode]
}
