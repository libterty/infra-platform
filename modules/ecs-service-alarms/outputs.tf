output "alarm_arns" {
  description = "告警 ARN 的 map，key 同〈告警清單〉的 key。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "告警名稱的 map，key 同〈告警清單〉的 key。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "dashboard_arn" {
  description = "dashboard ARN；`dashboard_name` 為 `null` 時是 `null`。"
  value       = one(aws_cloudwatch_dashboard.this[*].dashboard_arn)
}
