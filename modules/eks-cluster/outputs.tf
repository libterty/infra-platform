output "cluster_name" {
  description = "叢集名稱。"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "叢集 ARN。"
  value       = aws_eks_cluster.this.arn
}

output "endpoint" {
  description = "API server endpoint URL。"
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority_data" {
  description = "叢集 CA（base64），給 kubeconfig 與 kubernetes、helm provider 用。"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_issuer_url" {
  description = "叢集的 OIDC issuer URL，`iam-oidc-provider` 的輸入。"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_security_group_id" {
  description = "EKS 建的 cluster security group ID。"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "service_ipv4_cidr" {
  description = "叢集的 Kubernetes service CIDR（沒指定時 EKS 從 `10.100.0.0/16`、`172.20.0.0/16` 擇一）。"
  value       = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
}

output "node_group_names" {
  description = "managed node group 名稱的清單。"
  value       = [for g in aws_eks_node_group.this : g.node_group_name]
}

output "karpenter_interruption_queue_name" {
  description = "Karpenter interruption SQS queue 名稱；沒開 `karpenter` 時是 `null`。"
  value       = one(aws_sqs_queue.karpenter[*].name)
}

output "log_group_name" {
  description = "control plane log group 名稱。"
  value       = aws_cloudwatch_log_group.cluster.name
}
