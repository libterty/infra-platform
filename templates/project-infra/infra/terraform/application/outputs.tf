# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "cluster_name" {
  description = "ECS cluster name."
  value       = module.cluster.cluster_name
}

output "service_names" {
  description = "ECS service name by service."
  value       = { for s, m in module.service : s => m.service_name }
}
