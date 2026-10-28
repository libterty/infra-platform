# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "kms_key_arn" {
  description = "共用的 KMS key。"
  value       = module.kms.key_arn
}

output "alarm_topic_arn" {
  description = "告警 topic。每位 email 收件人要確認訂閱。"
  value       = module.alarm_topic.topic_arn
}

output "api_secret_arn" {
  description = "第三方 API key 的 secret 容器；值要在 Terraform 外用主控台或 CLI 寫入。"
  value       = module.secret["api_key"].arn
}

output "origin_verify_secret_arn" {
  description = "origin verify 值的 secret 容器；值要在 Terraform 外寫入，並跟 `web` stack 的 `TF_VAR_origin_verify_header_value` 一致。"
  value       = module.secret["origin_verify"].arn
}
