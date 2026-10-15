# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "role_arns" {
  description = "Role ARN by role: ecs_execution, rds_proxy, rds_monitoring."
  value       = { for k, m in module.role : k => m.arn }
}
