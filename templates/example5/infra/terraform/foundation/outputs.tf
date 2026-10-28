# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "kms_key_arn" {
  description = "共用的 KMS key。"
  value       = module.kms.key_arn
}

output "alarm_topic_arn" {
  description = "告警 topic。每位 email 收件人要確認訂閱。"
  value       = module.alarm_topic.topic_arn
}

output "flow_log_bucket_arn" {
  description = "VPC flow log 的 bucket。"
  value       = module.flow_log_bucket.arn
}

output "opensearch_master_secret_arn" {
  description = "OpenSearch master 帳密的 secret 容器；值要在 Terraform 外用主控台或 CLI 寫入。"
  value       = module.opensearch_master_secret.arn
}
