output "name" {
  description = "Log group name."
  value       = aws_cloudwatch_log_group.this.name
}

output "arn" {
  description = "Log group ARN."
  value       = aws_cloudwatch_log_group.this.arn
}
