# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "trail_arn" {
  description = "CloudTrail trail 的 ARN。"
  value       = module.trail.arn
}

output "trail_log_group_name" {
  description = "trail 的 CloudWatch Logs log group。"
  value       = module.trail_log_group.name
}

output "alarm_names" {
  description = "CloudTrail 告警（root 帳號使用、未授權的 API 呼叫）的 alarm 名稱。"
  value       = module.trail_alarms.alarm_names
}

output "config_recorder_name" {
  description = "Config recorder 的名稱。"
  value       = module.config_recorder.recorder_name
}
