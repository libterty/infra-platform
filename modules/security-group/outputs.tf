output "security_group_ids" {
  value       = tomap({ for k, sg in aws_security_group.this : k => sg.id })
  description = "SG ID，key 同 `security_groups`。"
}

output "security_group_arns" {
  value       = tomap({ for k, sg in aws_security_group.this : k => sg.arn })
  description = "SG ARN，key 同 `security_groups`。"
}
