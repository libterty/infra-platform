output "sampling_rule_arns" {
  description = "key 同 `sampling_rules` 的 map，值是 sampling rule ARN。"
  value       = { for k, r in aws_xray_sampling_rule.this : k => r.arn }
}

output "group_arns" {
  description = "key 同 `groups` 的 map，值是 group ARN。"
  value       = { for k, g in aws_xray_group.this : k => g.arn }
}
