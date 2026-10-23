output "name" {
  description = "log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}

output "arn" {
  description = "log group ARN。"
  value       = aws_cloudwatch_log_group.this.arn
}
