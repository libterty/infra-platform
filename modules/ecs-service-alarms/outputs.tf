output "alarm_arns" {
  description = "Alarm ARNs keyed by alarm."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Alarm names keyed by alarm."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "dashboard_arn" {
  description = "Dashboard ARN; null when dashboard_name is null."
  value       = one(aws_cloudwatch_dashboard.this[*].dashboard_arn)
}
