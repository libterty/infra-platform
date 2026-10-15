output "sampling_rule_arns" {
  description = "Sampling rule ARNs keyed by the sampling_rules key."
  value       = { for k, r in aws_xray_sampling_rule.this : k => r.arn }
}

output "group_arns" {
  description = "Group ARNs keyed by the groups key."
  value       = { for k, g in aws_xray_group.this : k => g.arn }
}
