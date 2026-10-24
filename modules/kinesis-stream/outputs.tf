output "name" {
  description = "stream 名稱。"
  value       = aws_kinesis_stream.this.name
}

output "arn" {
  description = "stream 的 ARN。"
  value       = aws_kinesis_stream.this.arn
}
