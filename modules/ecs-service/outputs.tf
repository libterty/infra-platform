output "service_name" {
  value       = local.service.name
  description = "ECS service 名稱。"
}

output "service_arn" {
  value       = local.service.id
  description = "ECS service ARN。"
}

output "cluster_name" {
  value       = local.cluster_name
  description = "從 `cluster_arn` 拆出的 cluster 名稱。"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.this.arn
  description = "task definition ARN，含 revision。"
}

output "task_definition_family" {
  value       = aws_ecs_task_definition.this.family
  description = "task definition family。"
}

output "container_name" {
  value       = "app"
  description = "主 container 名稱，固定 `app`。"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.this.name
  description = "service log group 名稱。"
}

output "log_group_arn" {
  value       = aws_cloudwatch_log_group.this.arn
  description = "service log group ARN。"
}

output "target_group_arn" {
  value       = local.target_group_arn
  description = "target group ARN：`target_group_arn` 模式是傳入的值，`listener_arn` 模式是 module 建的；不接 LB 時 `null`。"
}

output "target_group_arn_suffix" {
  value       = local.target_group_arn_suffix
  description = "`targetgroup/<name>/<id>`，給告警的 dimension 用；不接 LB 時 `null`。"
}

output "autoscaling_resource_id" {
  value       = aws_appautoscaling_target.this.resource_id
  description = "`service/<cluster>/<service>`，給在 module 外另加的 scaling policy 用。"
}
