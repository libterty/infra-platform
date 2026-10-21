locals {
  default_repositories = {
    load_balancer_controller = "https://aws.github.io/eks-charts"
    karpenter                = "oci://public.ecr.aws/karpenter"
    argo_rollouts            = "https://argoproj.github.io/argo-helm"
  }
  repositories = merge(local.default_repositories, var.chart_repository_overrides)

  # The release namespace of the local charts. Their objects are cluster scoped, so the release only needs a namespace
  # that always exists to hold the Helm release Secret.
  app_namespaces_release_namespace = "kube-system"

  local_chart_versions = {
    karpenter_defaults = yamldecode(file("${path.module}/charts/karpenter-defaults/Chart.yaml")).version
    app_namespaces     = yamldecode(file("${path.module}/charts/app-namespaces/Chart.yaml")).version
  }

  install_karpenter_defaults = var.karpenter == null ? false : (var.karpenter.default_node_class != null && var.karpenter.default_node_pool != null)
}

# atomic: a failed install is purged and a failed upgrade is rolled back; it implies wait, so the apply only succeeds
# once the controller pods are ready. A controller left half installed is worse than a failed apply.
# values goes through yamlencode so any nested structure works; set comes after values in Helm, so the explicit
# inputs below win over the same keys in values.
resource "helm_release" "load_balancer_controller" {
  count = var.load_balancer_controller == null ? 0 : 1

  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = local.repositories["load_balancer_controller"]
  chart      = "aws-load-balancer-controller"
  version    = var.load_balancer_controller.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode(var.load_balancer_controller.values)]

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.name", value = var.load_balancer_controller.service_account },
    { name = "replicaCount", value = tostring(var.load_balancer_controller.replica_count) },
  ]
}

# Karpenter and Argo Rollouts create Services. The controller registers a mutating webhook for Services, so it must be
# ready before them or their Service creation fails.
resource "helm_release" "karpenter" {
  count = var.karpenter == null ? 0 : 1

  name             = "karpenter"
  namespace        = var.karpenter.namespace
  create_namespace = true
  repository       = local.repositories["karpenter"]
  chart            = "karpenter"
  version          = var.karpenter.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  # values first; the set entries below win on conflict, as for the other releases.
  values = [yamlencode(var.karpenter.values)]

  set = [
    { name = "settings.clusterName", value = var.cluster_name },
    { name = "settings.interruptionQueue", value = var.karpenter.interruption_queue_name },
    { name = "serviceAccount.name", value = var.karpenter.service_account },
  ]

  depends_on = [helm_release.load_balancer_controller]
}

# NodePool and EC2NodeClass need the CRDs that the karpenter release installs.
resource "helm_release" "karpenter_defaults" {
  count = local.install_karpenter_defaults ? 1 : 0

  name      = "karpenter-defaults"
  namespace = var.karpenter.namespace
  chart     = "${path.module}/charts/karpenter-defaults"
  version   = local.local_chart_versions.karpenter_defaults

  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    nodeClass = {
      role              = var.karpenter.default_node_class.node_role_name
      subnetTags        = var.karpenter.default_node_class.subnet_discovery_tag
      securityGroupTags = var.karpenter.default_node_class.security_group_discovery_tag
      amiAlias          = var.karpenter.default_node_class.ami_alias
    }
    nodePool = {
      cpuLimit      = var.karpenter.default_node_pool.cpu_limit
      capacityTypes = var.karpenter.default_node_pool.capacity_types
    }
  })]

  depends_on = [helm_release.karpenter]
}

resource "helm_release" "argo_rollouts" {
  count = var.argo_rollouts == null ? 0 : 1

  name             = "argo-rollouts"
  namespace        = var.argo_rollouts.namespace
  create_namespace = true
  repository       = local.repositories["argo_rollouts"]
  chart            = "argo-rollouts"
  version          = var.argo_rollouts.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode(var.argo_rollouts.values)]

  depends_on = [helm_release.load_balancer_controller]
}

resource "helm_release" "app_namespaces" {
  count = length(var.app_namespaces) == 0 ? 0 : 1

  name      = "app-namespaces"
  namespace = local.app_namespaces_release_namespace
  chart     = "${path.module}/charts/app-namespaces"
  version   = local.local_chart_versions.app_namespaces

  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({ namespaces = var.app_namespaces })]
}
