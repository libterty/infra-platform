locals {
  # iam scopes the Pod Identity trust to this name (iam/roles.tf), so it must stay <project>-<env>.
  cluster_name = local.name_prefix

  # Namespaces and ServiceAccounts of the controllers are the eks-addons module defaults; the C5 stack keeps them.
  controller_identities = {
    lb_controller    = { namespace = "kube-system", service_account = "aws-load-balancer-controller", role_key = "lb_controller_role_arn" }
    keda             = { namespace = "keda", service_account = "keda-operator", role_key = "keda_role_arn" }
    cloudwatch_agent = { namespace = "amazon-cloudwatch", service_account = "cloudwatch-agent", role_key = "cloudwatch_agent_role_arn" }
  }

  pod_identity_associations = merge(
    {
      api    = { namespace = var.app_namespace, service_account = var.api_service_account, role_arn = module.shared.strings["api_pod_role_arn"] }
      worker = { namespace = var.app_namespace, service_account = var.worker_service_account, role_arn = module.shared.strings["worker_pod_role_arn"] }
    },
    { for k, c in local.controller_identities : k => { namespace = c.namespace, service_account = c.service_account, role_arn = module.shared.strings[c.role_key] } },
  )

  access_entries = merge(
    # No built-in NodePool and no node role on the cluster, so EKS creates no node entry; this one lets the
    # eks-addons NodeClasses join nodes (design v4 K4).
    {
      node = {
        principal_arn = module.shared.strings["eks_node_role_arn"]
        type          = "EC2"
        policies      = { auto_node = { policy = "AmazonEKSAutoNodePolicy", namespaces = [] } }
      }
    },
    # Keyed by ARN so reordering the list does not replace entries.
    {
      for a in var.cluster_admin_principal_arns : "admin-${a}" => {
        principal_arn = a
        type          = "STANDARD"
        policies      = { admin = { policy = "AmazonEKSClusterAdminPolicy", namespaces = [] } }
      }
    },
    {
      addons_apply = {
        principal_arn = var.addons_apply_principal_arn
        type          = "STANDARD"
        policies      = { admin = { policy = "AmazonEKSClusterAdminPolicy", namespaces = [] } }
      }
      ci_deploy = {
        principal_arn = var.ci_deploy_principal_arn
        type          = "STANDARD"
        policies      = { edit = { policy = "AmazonEKSEditPolicy", namespaces = [var.app_namespace] } }
      }
    },
  )
}

# Kubernetes secrets envelope encryption. EKS uses a grant that the identity creating the cluster makes, so that
# identity needs kms:CreateGrant and kms:DescribeKey on this key (the account root statement lets IAM grant them).
module "secrets_key" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/kms-key/aws"
  version = "~> 0.1.0"

  name        = "${local.cluster_name}-eks-secrets"
  description = "Secrets encryption of EKS cluster ${local.cluster_name}"
}

module "eks" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/eks-cluster/aws"
  version = "~> 0.2.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.shared.strings["eks_cluster_role_arn"]
  kms_key_arn        = module.secrets_key.key_arn

  # Private endpoint only (design v4 E10). The control-plane ENIs sit in the app subnets; eks_api lets the runners in.
  subnet_ids             = module.shared.lists["app_subnet_ids"]
  security_group_ids     = [module.shared.strings["eks_api_sg_id"]]
  endpoint_public_access = false

  # Auto Mode without built-in NodePools or a node role; eks-addons creates the NodeClasses and NodePools.
  auto_mode = {
    node_role_arn = null
    node_pools    = []
  }

  access_entries            = local.access_entries
  pod_identity_associations = local.pod_identity_associations
}
