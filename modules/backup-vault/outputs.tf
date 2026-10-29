output "arn" {
  description = "vault 的 ARN（`backup-plan` 跨 vault 複製時的 `copy_to.vault_arn`）。"
  value       = aws_backup_vault.this.arn
}

output "name" {
  description = "vault 的名稱（`backup-plan` 的 `vault_name`）。"
  value       = aws_backup_vault.this.name
}
