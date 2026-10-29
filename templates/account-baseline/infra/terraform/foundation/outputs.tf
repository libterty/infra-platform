# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "kms_key_arn" {
  description = "治理用的 KMS key。"
  value       = module.kms.key_arn
}

output "trail_bucket_name" {
  description = "CloudTrail 的 log bucket。"
  value       = module.log_bucket["trail"].bucket_name
}

output "config_bucket_name" {
  description = "Config 的 log bucket。"
  value       = module.log_bucket["config"].bucket_name
}

output "alert_topic_arn" {
  description = "資安告警 topic。每位 email 收件人要確認訂閱。"
  value       = module.alert_topic.topic_arn
}
