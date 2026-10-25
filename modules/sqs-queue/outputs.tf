output "queue_arn" {
  description = "主 queue 的 ARN。"
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "主 queue 的 URL。"
  value       = aws_sqs_queue.this.url
}

output "queue_name" {
  description = "主 queue 的名稱（FIFO 含 `.fifo`）。"
  value       = aws_sqs_queue.this.name
}

output "dlq_arn" {
  description = "DLQ 的 ARN。"
  value       = aws_sqs_queue.dlq.arn
}
