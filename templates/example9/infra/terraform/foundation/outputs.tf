# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "kms_key_arn" {
  description = "共用的 KMS key。"
  value       = module.kms.key_arn
}

output "artifact_bucket_name" {
  description = "pipeline artifact 的 bucket，物件 30 天後過期。"
  value       = module.artifact_bucket.bucket_name
}

output "alert_topic_arn" {
  description = "告警 topic。每位 email 收件人要確認訂閱。"
  value       = module.alert_topic.topic_arn
}

output "connection_arn" {
  description = "GitHub connection。建好時是 `PENDING`，要到 console 授權一次才會變 `AVAILABLE`。"
  value       = module.connection.arn
}

output "connection_status" {
  description = "GitHub connection 的狀態；不是 `AVAILABLE` 時 pipeline 的 Source stage 會失敗。"
  value       = module.connection.status
}
