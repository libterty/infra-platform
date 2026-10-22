locals {
  releases = merge(
    { for r in helm_release.load_balancer_controller : "load_balancer_controller" => r },
    { for r in helm_release.karpenter : "karpenter" => r },
    { for r in helm_release.karpenter_defaults : "karpenter_defaults" => r },
    { for r in helm_release.argo_rollouts : "argo_rollouts" => r },
    { for r in helm_release.app_namespaces : "app_namespaces" => r },
    { for r in helm_release.auto_mode_nodes : "auto_mode_nodes" => r },
    { for r in helm_release.system_network_policy : "system_network_policy" => r },
    { for r in helm_release.keda : "keda" => r },
    { for r in helm_release.cloudwatch_observability : "cloudwatch_observability" => r },
  )
}

output "releases" {
  description = "Name, namespace and chart version of each installed release, keyed by component (load_balancer_controller, karpenter, karpenter_defaults, argo_rollouts, app_namespaces, auto_mode_nodes, system_network_policy, keda, cloudwatch_observability). Components that are not installed are absent."
  value       = { for k, r in local.releases : k => { name = r.name, namespace = r.namespace, version = r.version } }
}
