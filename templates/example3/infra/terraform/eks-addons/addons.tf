locals {
  cluster_name = module.in.strings["cluster_name"]

  # Nodes get the EKS cluster group and the node group (design v4 K1); the app and eks-pod subnet tags come from network.
  node_subnet_terms = [{ tags = { "eks-node" = local.cluster_name } }]
  node_group_terms  = [{ id = module.in.strings["cluster_sg_id"] }, { id = module.shared.strings["node_sg_id"] }]

  system_taint = { key = "CriticalAddonsOnly", effect = "NoSchedule" }

  auto_mode = {
    node_role_name = regex("[^/]+$", module.shared.strings["eks_node_role_arn"])
    node_classes = {
      # api and worker: Pods get the app group, the same rules as the ECS tasks of example2.
      app = {
        subnet_selector_terms             = local.node_subnet_terms
        security_group_selector_terms     = local.node_group_terms
        pod_subnet_selector_terms         = [{ tags = { "eks-pod" = local.cluster_name } }]
        pod_security_group_selector_terms = [{ id = module.shared.strings["app_sg_id"] }]
        network_policy                    = "DefaultDeny"
      }
      system = {
        subnet_selector_terms         = local.node_subnet_terms
        security_group_selector_terms = local.node_group_terms
        network_policy                = "DefaultDeny"
      }
    }
    node_pools = {
      app    = { node_class = "app", taints = [], cpu_limit = var.app_pool_cpu_limit }
      system = { node_class = "system", taints = [local.system_taint], cpu_limit = var.system_pool_cpu_limit }
    }
  }

  # The CloudWatch DaemonSets are not placed: the chart default tolerates every taint, so they cover both pools (K3).
  system_placement = {
    node_selector = { "karpenter.sh/nodepool" = "system" }
    tolerations   = [merge(local.system_taint, { operator = "Exists" })]
  }

  # The control-plane ENIs and the interface endpoints sit in the app subnets (network stack).
  app_subnet_cidrs = module.shared.lists["app_subnet_cidrs"]
  network_policy = {
    service_cidr     = module.in.strings["service_cidr"]
    api_server_cidrs = local.app_subnet_cidrs
    aws_api_cidrs    = var.nat_mode == "none" ? local.app_subnet_cidrs : ["0.0.0.0/0"]
  }
}

module "addons" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eks-addons/aws"
  version = "~> 0.3.0"

  cluster_name = local.cluster_name
  region       = var.aws_region
  vpc_id       = module.shared.strings["vpc_id"]

  auto_mode        = local.auto_mode
  network_policy   = local.network_policy
  system_placement = local.system_placement

  # Namespaces and ServiceAccounts stay at the module defaults: the eks-cluster Pod Identity associations use them (C4-5).
  load_balancer_controller = {}
  keda                     = {}
  cloudwatch_observability = {}

  # CI deploys with AmazonEKSEditPolicy in this namespace only; the namespace and the CRD roles are made here (C5-1).
  app_namespaces      = { (module.in.strings["app_namespace"]) = {} }
  aggregate_crd_roles = true

  depends_on = [terraform_data.eks_contract_version]
}
