# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Private API server endpoint."
  value       = module.eks.endpoint
}
