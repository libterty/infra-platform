output "task_role_arns" {
  description = "Task role ARN by service."
  value       = { for s, m in module.task_role : s => m.arn }
}
