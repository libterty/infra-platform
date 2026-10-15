output "key_arn" {
  description = "ARN of the key."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "ID of the key."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Alias name, alias/<name>."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "ARN of the alias."
  value       = aws_kms_alias.this.arn
}
