output "cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "cluster 名稱。"
}

output "cluster_arn" {
  value       = aws_ecs_cluster.this.arn
  description = "cluster ARN，傳給 `ecs-service` 的 `cluster_arn`。"
}

output "cluster_id" {
  value       = aws_ecs_cluster.this.id
  description = "cluster id。"
}

output "service_connect_namespace_arn" {
  value       = one(aws_service_discovery_http_namespace.this[*].arn)
  description = "Service Connect namespace ARN；沒建時為 `null`。"
}
