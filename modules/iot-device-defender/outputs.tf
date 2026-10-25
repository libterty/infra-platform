output "scheduled_audit_arns" {
  description = "排程稽核名稱對應 ARN 的 map。"
  value       = { for name, a in awscc_iot_scheduled_audit.this : name => a.scheduled_audit_arn }
}

output "mitigation_action_arns" {
  description = "mitigation action 名稱對應 ARN 的 map。"
  value       = { for name, m in awscc_iot_mitigation_action.this : name => m.mitigation_action_arn }
}
