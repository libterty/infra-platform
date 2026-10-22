locals {
  shared_input_strings = {
    eks_api_sg_id             = "infra/eks_api_sg_id"
    eks_cluster_role_arn      = "infra/eks_cluster_role_arn"
    eks_node_role_arn         = "infra/eks_node_role_arn"
    api_pod_role_arn          = "infra/api_pod_role_arn"
    worker_pod_role_arn       = "infra/worker_pod_role_arn"
    lb_controller_role_arn    = "infra/lb_controller_role_arn"
    keda_role_arn             = "infra/keda_role_arn"
    cloudwatch_agent_role_arn = "infra/cloudwatch_agent_role_arn"
  }

  shared_input_lists = {
    app_subnet_ids = "infra/app_subnet_ids"
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
