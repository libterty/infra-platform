output "table_name" {
  description = "table 名稱。"
  value       = aws_dynamodb_table.this.name
}

output "arn" {
  description = "table 的 ARN。"
  value       = aws_dynamodb_table.this.arn
}

output "stream_arn" {
  description = "DynamoDB Streams 的 ARN；沒開 stream（`stream_view_type = null`）時是 `null`。"
  value       = var.stream_view_type == null ? null : aws_dynamodb_table.this.stream_arn
}
