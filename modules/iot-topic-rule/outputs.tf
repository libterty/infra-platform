output "rule_arns" {
  description = "rule 名稱 → rule 的 ARN。"
  value       = { for k, r in aws_iot_topic_rule.this : k => r.arn }
}

output "rule_names" {
  description = "所有 rule 的名稱。"
  value       = keys(aws_iot_topic_rule.this)
}
