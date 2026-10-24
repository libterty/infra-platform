output "name" {
  description = "delivery stream 名稱。"
  value       = aws_kinesis_firehose_delivery_stream.this.name
}

output "arn" {
  description = "delivery stream 的 ARN。"
  value       = aws_kinesis_firehose_delivery_stream.this.arn
}

output "log_group_name" {
  description = "module 建的 CloudWatch log group 名稱。"
  value       = aws_cloudwatch_log_group.this.name
}
