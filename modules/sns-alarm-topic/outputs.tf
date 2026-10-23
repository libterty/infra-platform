output "topic_arn" {
  description = "告警 topic 的 ARN，給告警的 `alarm_actions`、`ok_actions` 用。"
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "告警 topic 的名稱。"
  value       = aws_sns_topic.this.name
}

output "subscription_arns" {
  description = "email 訂閱的 ARN，key 為 email。"
  value       = { for e, s in aws_sns_topic_subscription.email : e => s.arn }
}
