output "key_arn" {
  description = "key 的 ARN。"
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "key 的 ID。"
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "alias 名稱，格式 `alias/<name>`。"
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "alias 的 ARN。"
  value       = aws_kms_alias.this.arn
}
