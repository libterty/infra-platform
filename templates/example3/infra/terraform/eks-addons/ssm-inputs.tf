locals {
  # The versioned EKS contract of the eks-cluster stack (design v4 §8.1).
  ssm_input_strings = {
    contract_version = "eks-cluster/contract_version"
    cluster_name     = "eks-cluster/cluster_name"
    cluster_endpoint = "eks-cluster/cluster_endpoint"
    cluster_ca_data  = "eks-cluster/cluster_ca_data"
    cluster_sg_id    = "eks-cluster/cluster_sg_id"
    service_cidr     = "eks-cluster/service_cidr"
    app_namespace    = "eks-cluster/app_namespace"
  }

  shared_input_strings = {
    vpc_id            = "infra/vpc_id"
    app_sg_id         = "infra/app_sg_id"
    node_sg_id        = "infra/node_sg_id"
    eks_node_role_arn = "infra/eks_node_role_arn"
  }

  shared_input_lists = {
    app_subnet_cidrs = "infra/app_subnet_cidrs"
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
