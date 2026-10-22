output "cluster_name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "endpoint" {
  description = "API server endpoint URL."
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority_data" {
  description = "Base64 encoded certificate authority of the cluster, for kubeconfig and the kubernetes and helm providers."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, the input of iam-oidc-provider."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "Cluster security group created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "service_ipv4_cidr" {
  description = "Kubernetes service CIDR of the cluster (EKS picks 10.100.0.0/16 or 172.20.0.0/16 when it is not set)."
  value       = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
}

output "node_group_names" {
  description = "Names of the managed node groups."
  value       = [for g in aws_eks_node_group.this : g.node_group_name]
}

output "karpenter_interruption_queue_name" {
  description = "Name of the Karpenter interruption queue; null without karpenter."
  value       = one(aws_sqs_queue.karpenter[*].name)
}

output "log_group_name" {
  description = "Control plane log group name."
  value       = aws_cloudwatch_log_group.cluster.name
}
