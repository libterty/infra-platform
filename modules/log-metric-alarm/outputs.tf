output "alarm_arns" {
  description = "Alarm ARNs keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Alarm names keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "metric_filter_names" {
  description = "Metric filter names keyed by the alarms key."
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => f.name }
}
