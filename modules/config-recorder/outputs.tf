output "recorder_name" {
  description = "configuration recorder 的名稱。"
  value       = aws_config_configuration_recorder.this.name
}

output "delivery_channel_name" {
  description = "delivery channel 的名稱。"
  value       = aws_config_delivery_channel.this.name
}

output "aggregator_arn" {
  description = "aggregator 的 ARN；沒有 `aggregator` 時是 `null`。"
  value       = one(aws_config_configuration_aggregator.this[*].arn)
}
