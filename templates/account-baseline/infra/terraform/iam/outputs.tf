# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "config_role_arn" {
  description = "Config recorder 用的 role。"
  value       = module.role["config"].arn
}

output "backup_role_arn" {
  description = "Backup plan 用的 role。"
  value       = module.role["backup"].arn
}

output "trail_logs_role_arn" {
  description = "CloudTrail 寫 CloudWatch Logs 用的 role。"
  value       = module.role["trail_logs"].arn
}
