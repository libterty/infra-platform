locals {
  releases = merge(
    { for r in helm_release.load_balancer_controller : "load_balancer_controller" => r },
    { for r in helm_release.karpenter : "karpenter" => r },
    { for r in helm_release.karpenter_defaults : "karpenter_defaults" => r },
    { for r in helm_release.argo_rollouts : "argo_rollouts" => r },
    { for r in helm_release.app_namespaces : "app_namespaces" => r },
  )
}

output "releases" {
  description = "Name, namespace and chart version of each installed release, keyed by component (load_balancer_controller, karpenter, karpenter_defaults, argo_rollouts, app_namespaces). Components that are not installed are absent."
  value       = { for k, r in local.releases : k => { name = r.name, namespace = r.namespace, version = r.version } }
}
