output "topic_arn" {
  description = "ARN of the alarm topic; pass it to alarms as alarm_actions and ok_actions."
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Name of the alarm topic."
  value       = aws_sns_topic.this.name
}

output "subscription_arns" {
  description = "Email subscription ARNs keyed by email address."
  value       = { for e, s in aws_sns_topic_subscription.email : e => s.arn }
}
