output "alarm_arns" {
  description = "Alarm ARNs keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Alarm names keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "metric_filter_names" {
  description = "Metric filter names keyed by the alarms and metrics keys."
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => f.name }
}

output "metric_names" {
  description = "Metric names keyed by the alarms and metrics keys; use them with namespace for dashboards or alarms managed elsewhere."
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => one(f.metric_transformation).name }
}
