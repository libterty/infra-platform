output "service_name" {
  value       = aws_ecs_service.this.name
  description = "ECS service name."
}

output "service_arn" {
  value       = aws_ecs_service.this.id
  description = "ECS service ARN."
}

output "cluster_name" {
  value       = local.cluster_name
  description = "Cluster name, split from cluster_arn."
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.this.arn
  description = "Task definition ARN including the revision."
}

output "task_definition_family" {
  value       = aws_ecs_task_definition.this.family
  description = "Task definition family."
}

output "container_name" {
  value       = "app"
  description = "Container name; fixed."
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.this.name
  description = "Service log group name."
}

output "log_group_arn" {
  value       = aws_cloudwatch_log_group.this.arn
  description = "Service log group ARN."
}

output "target_group_arn" {
  value       = local.target_group_arn
  description = "Target group ARN: the input in target_group_arn mode, the created one in listener_arn mode, null without a load balancer."
}

output "target_group_arn_suffix" {
  value       = local.target_group_arn_suffix
  description = "targetgroup/<name>/<id>, for alarm dimensions; null without a load balancer."
}

output "autoscaling_resource_id" {
  value       = aws_appautoscaling_target.this.resource_id
  description = "service/<cluster>/<service>, for extra scaling policies defined outside the module."
}
