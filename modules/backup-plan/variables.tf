variable "name" {
  type        = string
  description = "backup plan 的名稱，也是 selection 的名稱，1–50 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,50}$", var.name))
    error_message = "name must be 1-50 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "vault_name" {
  type        = string
  description = "備份存放的 vault 名稱（`backup-vault` 的 `name` 輸出），不是 ARN。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,50}$", var.vault_name))
    error_message = "vault_name must be a backup vault name (2-50 chars of letters, digits, underscores or hyphens), not an ARN."
  }
}

variable "role_arn" {
  type        = string
  description = "AWS Backup 備份與複製時用的 IAM role ARN，信任 `backup.amazonaws.com`。module 不建 role，在 `iam` stack 用 `iam-role` 建。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "rules" {
  type = map(object({
    schedule                  = string
    start_window_minutes      = optional(number)
    completion_window_minutes = optional(number)
    delete_after_days         = optional(number)
    cold_storage_after_days   = optional(number)
    enable_continuous_backup  = optional(bool, false)
    copy_to = optional(object({
      vault_arn         = string
      delete_after_days = optional(number)
    }))
  }))
  description = "備份規則，至少一個，key 是規則名稱（1–50 字元，限英數字、`_`、`-`、`.`）。`schedule` 是 `cron(...)`（UTC）；`start_window_minutes`、`completion_window_minutes` 不給用 AWS 的預設；`delete_after_days` 不給就不刪；`cold_storage_after_days` 有值時 `delete_after_days` 至少要再多 90 天；`enable_continuous_backup = true` 時 `delete_after_days` 必填且 1–35（加上冷儲存的 90 天規定，等於不能搭配冷儲存）；`copy_to` 把每份備份複製到另一個 vault（`vault_arn`），`delete_after_days` 是副本的保留天數。"

  validation {
    condition     = length(var.rules) >= 1
    error_message = "rules must have at least one entry."
  }

  validation {
    condition     = alltrue([for k, _ in var.rules : can(regex("^[a-zA-Z0-9_.-]{1,50}$", k))])
    error_message = "rule names must be 1-50 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, r in var.rules : can(regex("^cron\\(.+\\)$", r.schedule))])
    error_message = "rule schedule must be a cron(...) expression."
  }

  validation {
    condition = alltrue([for _, r in var.rules : alltrue([
      for n in [r.start_window_minutes, r.completion_window_minutes, r.delete_after_days, r.cold_storage_after_days, try(r.copy_to.delete_after_days, null)] :
      n == null ? true : (n >= 1 && n == floor(n))
    ])])
    error_message = "rule windows and day counts must be positive whole numbers."
  }

  validation {
    condition = alltrue([for _, r in var.rules :
      r.cold_storage_after_days == null || r.delete_after_days == null ? true : r.delete_after_days >= r.cold_storage_after_days + 90
    ])
    error_message = "rule delete_after_days must be at least cold_storage_after_days + 90 (AWS keeps cold storage for at least 90 days)."
  }

  validation {
    condition = alltrue([for _, r in var.rules :
      !r.enable_continuous_backup || (r.delete_after_days != null && try(r.delete_after_days <= 35, false))
    ])
    error_message = "rules with enable_continuous_backup need delete_after_days between 1 and 35."
  }

  validation {
    condition = alltrue([for _, r in var.rules :
      r.copy_to == null || try(can(regex("^arn:aws[a-z-]*:backup:[a-z0-9-]+:[0-9]{12}:backup-vault:[a-zA-Z0-9_-]{2,50}$", r.copy_to.vault_arn)), false)
    ])
    error_message = "rule copy_to vault_arn must be a backup vault ARN (arn:<partition>:backup:<region>:<account>:backup-vault:<name>)."
  }
}

variable "selection_tags" {
  type        = map(string)
  description = "用 tag 選要備份的資源，key 是 tag key、value 是 tag 值（完全相等），至少一個。給多個時，符合任一個 tag 的資源都會被備份。範本用 `{ backup = \"daily\" }`。"

  validation {
    condition     = length(var.selection_tags) >= 1
    error_message = "selection_tags must have at least one tag."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "backup plan 所在的 region，要跟 `vault_name` 的 vault 相同；`null`（預設）用 provider 的 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "backup plan 的 tag；`Name` 由 module 加上。這些 tag 不會加到 recovery point。"
}
