locals {
  default_repositories = {
    load_balancer_controller = "https://aws.github.io/eks-charts"
    karpenter                = "oci://public.ecr.aws/karpenter"
    argo_rollouts            = "https://argoproj.github.io/argo-helm"
    keda                     = "https://kedacore.github.io/charts"
    cloudwatch_observability = "https://aws-observability.github.io/helm-charts"
  }
  repositories = merge(local.default_repositories, var.chart_repository_overrides)

  # The release namespace of the local charts. Their objects are cluster scoped (or carry their own namespace), so the
  # release only needs a namespace that always exists to hold the Helm release Secret.
  local_chart_release_namespace    = "kube-system"
  app_namespaces_release_namespace = local.local_chart_release_namespace

  local_chart_versions = {
    karpenter_defaults    = yamldecode(file("${path.module}/charts/karpenter-defaults/Chart.yaml")).version
    app_namespaces        = yamldecode(file("${path.module}/charts/app-namespaces/Chart.yaml")).version
    auto_mode_nodes       = yamldecode(file("${path.module}/charts/auto-mode-nodes/Chart.yaml")).version
    system_network_policy = yamldecode(file("${path.module}/charts/system-network-policy/Chart.yaml")).version
    crd_role_aggregation  = yamldecode(file("${path.module}/charts/crd-role-aggregation/Chart.yaml")).version
  }

  install_karpenter_defaults = var.karpenter == null ? false : (var.karpenter.default_node_class != null && var.karpenter.default_node_pool != null)

  # system_placement goes into the values of the LB Controller and KEDA, after the user values, so it wins on conflict.
  # Unset toleration fields are dropped: a null key would be rendered as `key: null`.
  placement_values = {
    for k, v in {
      nodeSelector = try(var.system_placement.node_selector, {})
      tolerations  = [for t in try(var.system_placement.tolerations, []) : { for tk, tv in t : tk => tv if tv != null }]
    } : k => v if var.system_placement != null
  }

  # Auto Mode handles Service (type LoadBalancer) and Ingress itself. Set wins over values in Helm, so these cannot be
  # turned back on through load_balancer_controller.values.
  lbc_auto_mode_sets = var.auto_mode == null ? [] : [
    { name = "enableServiceMutatorWebhook", value = "false" },
    { name = "createIngressClassResource", value = "false" },
  ]

  # A selector term carries either id or tags; drop the unset one so the chart sees only what is set.
  auto_mode_node_classes = {
    for class_name, c in(var.auto_mode == null ? {} : var.auto_mode.node_classes) : class_name => {
      subnetSelectorTerms           = [for t in c.subnet_selector_terms : { for k, v in t : k => v if v != null }]
      securityGroupSelectorTerms    = [for t in c.security_group_selector_terms : { for k, v in t : k => v if v != null }]
      podSubnetSelectorTerms        = [for t in c.pod_subnet_selector_terms : { for k, v in t : k => v if v != null }]
      podSecurityGroupSelectorTerms = [for t in c.pod_security_group_selector_terms : { for k, v in t : k => v if v != null }]
      networkPolicy                 = c.network_policy
      networkPolicyEventLogs        = c.network_policy_event_logs
    }
  }

  # System NetworkPolicy rules. try() keeps these evaluable when network_policy is null; they are then never used.
  pod_identity_agent_cidr = "169.254.170.23/32"
  np_api_server_cidrs     = try(var.network_policy.api_server_cidrs, [])
  np_dns_cidrs            = try(["${cidrhost(var.network_policy.service_cidr, 10)}/32"], [])
  np_aws_api_cidrs        = try(var.network_policy.aws_api_cidrs, [])

  np_egress_base = [
    { cidrs = local.np_api_server_cidrs, sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
    { cidrs = local.np_dns_cidrs, sameNamespace = false, ports = [{ port = 53, protocol = "UDP" }, { port = 53, protocol = "TCP" }] },
  ]
  # AWS APIs through the VPC endpoints, and the Pod Identity agent that hands out the credentials.
  np_egress_aws = [
    { cidrs = local.np_aws_api_cidrs, sameNamespace = false, ports = [{ port = 443, protocol = "TCP" }] },
    { cidrs = [local.pod_identity_agent_cidr], sameNamespace = false, ports = [{ port = 80, protocol = "TCP" }] },
  ]

  # One policy per installed component. The LB Controller shares kube-system with Pods this module does not own, so its
  # policy selects only its own Pods; the other two own their namespace and select every Pod in it.
  np_components = {
    load_balancer_controller = {
      enabled      = var.load_balancer_controller != null
      namespace    = "kube-system"
      pod_selector = { "app.kubernetes.io/name" = "aws-load-balancer-controller" }
      # Webhook (chart value webhookBindPort, default 9443).
      ingress = [{ cidrs = local.np_api_server_cidrs, sameNamespace = false, ports = [{ port = 9443, protocol = "TCP" }] }]
      egress  = concat(local.np_egress_base, local.np_egress_aws)
    }
    keda = {
      enabled      = var.keda != null
      namespace    = var.keda == null ? "keda" : var.keda.namespace
      pod_selector = {}
      ingress = [
        # Metrics API server (service.portHttpsTarget 6443) and admission webhooks (webhooks.port 9443); the API server calls both.
        { cidrs = local.np_api_server_cidrs, sameNamespace = false, ports = [{ port = 6443, protocol = "TCP" }, { port = 9443, protocol = "TCP" }] },
        # The metrics server reads from the operator over gRPC (operator.metricsServiceTargetPort 9666).
        { cidrs = [], sameNamespace = true, ports = [{ port = 9666, protocol = "TCP" }] },
      ]
      egress = concat(local.np_egress_base, local.np_egress_aws, [
        { cidrs = [], sameNamespace = true, ports = [{ port = 9666, protocol = "TCP" }] },
      ])
    }
    cloudwatch_observability = {
      enabled      = var.cloudwatch_observability != null
      namespace    = var.cloudwatch_observability == null ? "amazon-cloudwatch" : var.cloudwatch_observability.namespace
      pod_selector = {}
      # Operator webhook (manager.ports.webhookPort 9443). The agent and Fluent Bit DaemonSets run with hostNetwork,
      # which NetworkPolicy does not apply to.
      ingress = [{ cidrs = local.np_api_server_cidrs, sameNamespace = false, ports = [{ port = 9443, protocol = "TCP" }] }]
      egress  = concat(local.np_egress_base, local.np_egress_aws)
    }
  }

  np_policies = {
    for k, c in local.np_components : k => {
      namespace   = c.namespace
      podSelector = c.pod_selector
      ingress     = c.ingress
      egress      = c.egress
    } if var.network_policy != null && c.enabled
  }

  # kube-system exists; the other namespaces must exist before the controller is installed, so the chart creates them.
  np_namespaces = sort(distinct([for _, p in local.np_policies : p.namespace if p.namespace != "kube-system"]))
}

# NodeClass and NodePool of Auto Mode. Nothing else in this module needs to exist first.
resource "helm_release" "auto_mode_nodes" {
  count = var.auto_mode == null ? 0 : 1

  name      = "auto-mode-nodes"
  namespace = local.local_chart_release_namespace
  chart     = "${path.module}/charts/auto-mode-nodes"
  version   = local.local_chart_versions.auto_mode_nodes

  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    nodeRoleName = var.auto_mode.node_role_name
    nodeClasses  = local.auto_mode_node_classes
    nodePools = {
      for name, p in var.auto_mode.node_pools : name => {
        nodeClass          = p.node_class
        taints             = [for t in p.taints : { for k, v in t : k => v if v != null }]
        labels             = p.labels
        capacityTypes      = p.capacity_types
        instanceCategories = p.instance_categories
        architectures      = p.architectures
        cpuLimit           = p.cpu_limit
      }
    }
  })]
}

# Turns the NetworkPolicy controller on and allows the traffic of the system components under DefaultDeny. It depends on
# the node pools so that the install order node pools, policy, controllers is explicit.
resource "helm_release" "system_network_policy" {
  count = var.network_policy == null ? 0 : 1

  name      = "system-network-policy"
  namespace = local.local_chart_release_namespace
  chart     = "${path.module}/charts/system-network-policy"
  version   = local.local_chart_versions.system_network_policy

  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({
    enableNetworkPolicyController = true
    namespaces                    = local.np_namespaces
    policies                      = local.np_policies
  })]

  depends_on = [helm_release.auto_mode_nodes]
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

  values = [yamlencode(merge(var.load_balancer_controller.values, local.placement_values))]

  set = concat([
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.name", value = var.load_balancer_controller.service_account },
    { name = "replicaCount", value = tostring(var.load_balancer_controller.replica_count) },
  ], local.lbc_auto_mode_sets)

  # Install order: node pools, then the NetworkPolicy setup, then the controllers. Without the pools there is nowhere
  # to run; with DefaultDeny and no policy the controller cannot reach the API server and its webhook is not reachable.
  # tests/check-ordering.sh verifies these edges.
  depends_on = [helm_release.auto_mode_nodes, helm_release.system_network_policy]
}

# KEDA creates Services and webhooks, so like Karpenter and Argo Rollouts it comes after the LB Controller; the node
# pools and the NetworkPolicy setup come first. The Pod Identity association for its CloudWatch scaler is made in
# eks-cluster, on the operator service account.
resource "helm_release" "keda" {
  count = var.keda == null ? 0 : 1

  name             = "keda"
  namespace        = var.keda.namespace
  create_namespace = true
  repository       = local.repositories["keda"]
  chart            = "keda"
  version          = var.keda.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode(merge(var.keda.values, local.placement_values))]

  set = concat([
    { name = "serviceAccount.operator.name", value = var.keda.service_account },
  ], var.aggregate_crd_roles ? [{ name = "rbac.aggregateToDefaultRoles", value = "true" }] : [])

  depends_on = [helm_release.auto_mode_nodes, helm_release.system_network_policy, helm_release.load_balancer_controller]
}

# No placement: the chart default tolerates every taint, which the DaemonSets need to cover both the app and the system
# nodes. The agent and Fluent Bit share one ServiceAccount in this chart (agent.serviceAccount.name).
resource "helm_release" "cloudwatch_observability" {
  count = var.cloudwatch_observability == null ? 0 : 1

  name             = "amazon-cloudwatch-observability"
  namespace        = var.cloudwatch_observability.namespace
  create_namespace = true
  repository       = local.repositories["cloudwatch_observability"]
  chart            = "amazon-cloudwatch-observability"
  version          = var.cloudwatch_observability.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = [yamlencode(var.cloudwatch_observability.values)]

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "agent.serviceAccount.name", value = var.cloudwatch_observability.service_account },
    { name = "containerInsights.enabled", value = "true" },
    { name = "containerLogs.enabled", value = tostring(var.cloudwatch_observability.container_logs) },
    { name = "applicationSignals.enabled", value = tostring(var.cloudwatch_observability.application_signals) },
  ]

  depends_on = [helm_release.auto_mode_nodes, helm_release.system_network_policy, helm_release.load_balancer_controller]
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

# Roles only, no CRD needed to install them; it follows the controller so the roles appear together with the CRD.
resource "helm_release" "crd_role_aggregation" {
  count = var.aggregate_crd_roles && var.load_balancer_controller != null ? 1 : 0

  name      = "crd-role-aggregation"
  namespace = local.local_chart_release_namespace
  chart     = "${path.module}/charts/crd-role-aggregation"
  version   = local.local_chart_versions.crd_role_aggregation

  atomic          = true
  cleanup_on_fail = true
  timeout         = 300

  values = [yamlencode({ targetGroupBindings = true })]

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
