# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "task_role_arns" {
  description = "Task role ARN by service."
  value       = { for s, m in module.task_role : s => m.arn }
}
