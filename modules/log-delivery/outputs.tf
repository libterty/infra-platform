output "source_names" {
  description = "Delivery source name for each key in sources."
  value       = { for k, s in aws_cloudwatch_log_delivery_source.this : k => s.name }
}

output "destination_arns" {
  description = "Delivery destination ARN for each key in destinations."
  value       = { for k, d in aws_cloudwatch_log_delivery_destination.this : k => d.arn }
}

output "delivery_ids" {
  description = "Delivery id for each key in deliveries."
  value       = { for k, d in aws_cloudwatch_log_delivery.this : k => d.id }
}
