output "rule_arn" {
  description = "rule 的 ARN；給 `sqs-queue` 的 `allowed_source_arns`。"
  value       = aws_cloudwatch_event_rule.this.arn
}

output "rule_name" {
  description = "rule 名稱。"
  value       = aws_cloudwatch_event_rule.this.name
}
