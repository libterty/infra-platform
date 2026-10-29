# For people running terraform output. Downstream stacks never read these; cross-stack values go through SSM only.
output "guardduty_detector_id" {
  description = "GuardDuty detector 的 ID。"
  value       = module.guardduty.detector_id
}

output "securityhub_standards_subscription_arns" {
  description = "Security Hub 已訂閱標準的 subscription ARN。"
  value       = module.securityhub.standards_subscription_arns
}

output "inspector_resource_types" {
  description = "Inspector 啟用的掃描類型。"
  value       = module.inspector.enabled_resource_types
}

output "finding_rule_names" {
  description = "把高嚴重度 finding 送到告警 topic 的 EventBridge rule。"
  value       = { for k, m in module.finding_rule : k => m.rule_name }
}
