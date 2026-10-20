output "alarm_arns" {
  description = "Alarm ARNs keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Alarm names keyed by the alarms key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}
