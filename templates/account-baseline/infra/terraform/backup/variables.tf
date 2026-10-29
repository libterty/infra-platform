variable "vault_min_retention_days" {
  description = "vault lock（governance 模式）的最短保留天數；比這個短的 recovery point 不准建立。"
  type        = number

  validation {
    condition     = var.vault_min_retention_days >= 1 && var.vault_min_retention_days == floor(var.vault_min_retention_days)
    error_message = "vault_min_retention_days must be a whole number of at least 1."
  }
}

variable "backup_delete_after_days" {
  description = "每日備份的保留天數，要介於 `vault_min_retention_days` 與 365（vault lock 的最長保留天數）之間。"
  type        = number

  # The vault lock rejects backup jobs whose retention is outside its range, so the plan must stay inside it.
  validation {
    condition = (
      var.backup_delete_after_days == floor(var.backup_delete_after_days) &&
      var.backup_delete_after_days >= var.vault_min_retention_days &&
      var.backup_delete_after_days <= 365
    )
    error_message = "backup_delete_after_days must be a whole number between vault_min_retention_days and 365."
  }
}
