output "alarm_arns" {
  description = "key 同 `alarms` 的 map，值是 alarm ARN。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "key 同 `alarms` 的 map，值是 alarm 名稱。"
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "metric_filter_names" {
  description = "key 為 `alarms` 與 `metrics` 的 key 的 map，值是 metric filter 名稱。"
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => f.name }
}

output "metric_names" {
  description = "key 為 `alarms` 與 `metrics` 的 key 的 map，值是指標名稱；搭配 `namespace` 給 dashboard 或在別處管理的告警用。"
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => one(f.metric_transformation).name }
}
