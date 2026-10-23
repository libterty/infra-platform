locals {
  is_dev = var.env == "dev"

  # The EKS cluster of the eks-cluster stack is named after the stack prefix; Pod Identity roles trust only it.
  cluster_name = local.name_prefix
  cluster_arn  = "arn:aws:eks:${local.region}:${local.account_id}:cluster/${local.cluster_name}"
  pod_trust    = { service_principals = ["pods.eks.amazonaws.com"], source_account = local.account_id, source_arn = local.cluster_arn, tag_session = true }

  roles = merge(
    {
      import_extract = {
        name  = "${local.name_prefix}-import-extract"
        trust = { service_principals = ["lambda.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      import_load = {
        name  = "${local.name_prefix}-import-load"
        trust = { service_principals = ["lambda.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      agent_runtime = {
        name  = "${local.name_prefix}-agent-runtime"
        trust = { service_principals = ["bedrock-agentcore.amazonaws.com"], source_account = local.account_id, source_arn = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:*" }
      }
    },
    # EKS roles (design v4 §4, §8.1).
    {
      # The AWS trust policies of the Auto Mode cluster and node roles carry no aws:SourceAccount condition.
      eks_cluster = {
        name  = "${local.name_prefix}-eks-cluster"
        trust = { service_principals = ["eks.amazonaws.com"], source_account = null, source_arn = null, tag_session = true }
        managed_policy_arns = [
          "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
          "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
          "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
          "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
          "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
        ]
      }
      eks_node = {
        name                = "${local.name_prefix}-eks-node"
        trust               = { service_principals = ["ec2.amazonaws.com"], source_account = null, source_arn = null, tag_session = false }
        managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"]
      }
      api_pod          = { name = "${local.name_prefix}-api-pod", trust = local.pod_trust, managed_policy_arns = [] }
      worker_pod       = { name = "${local.name_prefix}-worker-pod", trust = local.pod_trust, managed_policy_arns = [] }
      lb_controller    = { name = "${local.name_prefix}-lb-controller", trust = local.pod_trust, managed_policy_arns = [] }
      keda             = { name = "${local.name_prefix}-keda", trust = local.pod_trust, managed_policy_arns = [] }
      cloudwatch_agent = { name = "${local.name_prefix}-cloudwatch-agent", trust = local.pod_trust, managed_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"] }
    },
    local.is_dev ? {
      eval_batch = {
        name  = "${local.name_prefix}-eval-batch"
        trust = { service_principals = ["bedrock.amazonaws.com"], source_account = local.account_id, source_arn = "arn:aws:bedrock:${local.region}:${local.account_id}:model-invocation-job/*" }
      }
    } : {},
  )
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.4.0"

  for_each = local.roles

  name = each.value.name
  trust = {
    service_principals = each.value.trust.service_principals
    source_account     = each.value.trust.source_account
    source_arn         = each.value.trust.source_arn
    tag_session        = try(each.value.trust.tag_session, false)
  }
  managed_policy_arns = try(each.value.managed_policy_arns, [])
  inline_policies = merge(
    length(local.statements[each.key]) == 0 ? {} : {
      permissions = jsonencode({ Version = "2012-10-17", Statement = local.statements[each.key] })
    },
    contains(keys(local.controller_policies), each.key) ? { controller = local.controller_policies[each.key] } : {},
  )
}

# Official controller policies; no resources. The cluster name scopes the LB Controller policy to this cluster.
module "eks_policies" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eks-iam-policies/aws"
  version = "~> 0.2.0"

  cluster_name = local.cluster_name
  region       = local.region
  account_id   = local.account_id
}

locals {
  controller_policies = {
    lb_controller = module.eks_policies.load_balancer_controller_policy_json
    keda          = module.eks_policies.keda_cloudwatch_policy_json
  }
}
