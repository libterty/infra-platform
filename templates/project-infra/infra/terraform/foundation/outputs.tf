output "kms_key_arn" {
  description = "Shared KMS key."
  value       = module.kms.key_arn
}

output "alarm_topic_arn" {
  description = "Alarm topic. Each email recipient must confirm the subscription."
  value       = module.alarm_topic.topic_arn
}

output "app_secret_arn" {
  description = "Secret container; write the value with the console or the CLI."
  value       = aws_secretsmanager_secret.app.arn
}

output "flow_log_bucket_arn" {
  description = "Bucket for VPC flow logs."
  value       = module.log_bucket["flow_log"].arn
}

output "alb_log_bucket_name" {
  description = "Bucket for ALB access logs."
  value       = module.log_bucket["alb_log"].bucket_name
}
