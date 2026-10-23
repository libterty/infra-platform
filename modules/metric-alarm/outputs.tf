output "alarm_arns" {
  description = "key 同 `alarms` 的 map，值是 alarm ARN。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "key 同 `alarms` 的 map，值是 alarm 名稱。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}
