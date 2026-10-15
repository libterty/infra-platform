output "security_group_ids" {
  value       = tomap({ for k, sg in aws_security_group.this : k => sg.id })
  description = "Security group ID by the key used in security_groups."
}

output "security_group_arns" {
  value       = tomap({ for k, sg in aws_security_group.this : k => sg.arn })
  description = "Security group ARN by the key used in security_groups."
}
