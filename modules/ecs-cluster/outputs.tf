output "cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "Cluster name."
}

output "cluster_arn" {
  value       = aws_ecs_cluster.this.arn
  description = "Cluster ARN; pass to ecs-service as cluster_arn."
}

output "cluster_id" {
  value       = aws_ecs_cluster.this.id
  description = "Cluster id."
}

output "service_connect_namespace_arn" {
  value       = one(aws_service_discovery_http_namespace.this[*].arn)
  description = "Service Connect namespace ARN; null when none was created."
}
