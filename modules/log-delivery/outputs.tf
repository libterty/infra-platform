output "source_names" {
  description = "key 同 `sources` 的 map，值是 delivery source 名稱。"
  value       = { for k, s in aws_cloudwatch_log_delivery_source.this : k => s.name }
}

output "destination_arns" {
  description = "key 同 `destinations` 的 map，值是 delivery destination ARN。"
  value       = { for k, d in aws_cloudwatch_log_delivery_destination.this : k => d.arn }
}

output "delivery_ids" {
  description = "key 同 `deliveries` 的 map，值是 delivery id。"
  value       = { for k, d in aws_cloudwatch_log_delivery.this : k => d.id }
}
