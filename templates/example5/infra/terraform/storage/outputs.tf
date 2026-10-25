# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "bucket_names" {
  description = "bucket 名稱，key 為 telemetry、greengrass_artifacts、ota、ml。"
  value       = { for k, b in module.bucket : k => b.bucket_name }
}

output "stream_name" {
  description = "Kinesis stream 名稱。"
  value       = module.stream.name
}

output "queue_urls" {
  description = "SQS queue URL，key 為 rule_errors、model_approved。"
  value       = { for k, q in module.queue : k => q.queue_url }
}
