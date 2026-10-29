variable "name" {
  type        = string
  description = "vault 名稱，2–50 字元，限英數字、`_`、`-`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{2,50}$", var.name))
    error_message = "name must be 2-50 chars of letters, digits, underscores or hyphens."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "加密 recovery point 用的客戶管理 KMS key ARN（symmetric），必填，不用 AWS Backup 的預設 key。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  nullable    = false
  description = "destroy 時是否連同 vault 裡的 recovery point 一起刪（預設 `false`）。`deny_delete_recovery_points = true` 或有 vault lock 時，recovery point 仍然刪不掉。"
}

variable "deny_delete_recovery_points" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否建 vault policy，對所有 principal deny `backup:DeleteRecoveryPoint`、`backup:UpdateRecoveryPointLifecycle`、`backup:PutBackupVaultAccessPolicy`（預設 `true`）。recovery point 仍會照 backup plan 的生命週期到期刪除。"
}

variable "lock" {
  type = object({
    min_retention_days      = optional(number)
    max_retention_days      = optional(number)
    changeable_for_days     = optional(number)
    compliance_acknowledged = optional(bool, false)
  })
  default     = null
  description = "vault lock；`null`（預設）不鎖。`min_retention_days`（1 以上）與 `max_retention_days`（36500 以下）至少給一個。不給 `changeable_for_days` 是 governance 模式，有權限的人仍可移除 lock；給了就是 compliance 模式，3–36500 天的冷卻期過後連 root 與 AWS 都改不了、刪不掉，所以要同時寫 `compliance_acknowledged = true`。"

  validation {
    condition     = var.lock == null || try(var.lock.min_retention_days != null || var.lock.max_retention_days != null, false)
    error_message = "lock needs min_retention_days, max_retention_days or both."
  }

  validation {
    condition = var.lock == null || try(
      (var.lock.min_retention_days == null || (var.lock.min_retention_days >= 1 && var.lock.min_retention_days == floor(var.lock.min_retention_days))) &&
      (var.lock.max_retention_days == null || (var.lock.max_retention_days <= 36500 && var.lock.max_retention_days >= 1 && var.lock.max_retention_days == floor(var.lock.max_retention_days))) &&
      (var.lock.min_retention_days == null || var.lock.max_retention_days == null || var.lock.min_retention_days <= var.lock.max_retention_days),
      false
    )
    error_message = "lock min_retention_days and max_retention_days must be whole numbers between 1 and 36500, with min_retention_days <= max_retention_days."
  }

  validation {
    condition     = var.lock == null || try(var.lock.changeable_for_days == null || var.lock.compliance_acknowledged, false)
    error_message = "lock changeable_for_days selects compliance mode, which can never be undone after the cooling-off period; set compliance_acknowledged = true to confirm."
  }

  validation {
    condition     = var.lock == null || try(var.lock.changeable_for_days == null || (var.lock.changeable_for_days >= 3 && var.lock.changeable_for_days <= 36500 && var.lock.changeable_for_days == floor(var.lock.changeable_for_days)), false)
    error_message = "lock changeable_for_days must be a whole number between 3 and 36500."
  }
}

variable "notifications" {
  type = object({
    sns_topic_arn = string
    events        = list(string)
  })
  default     = null
  description = "vault 事件通知；`null`（預設）不通知。`sns_topic_arn` 是同帳號的 standard topic（不支援 FIFO），topic policy 要允許 `backup.amazonaws.com` 發佈；`events` 至少一個，值照 `PutBackupVaultNotifications` 的清單，例如 `BACKUP_JOB_COMPLETED`、`COPY_JOB_FAILED`、`RESTORE_JOB_COMPLETED`。"

  validation {
    condition     = var.notifications == null || try(can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]{1,256}$", var.notifications.sns_topic_arn)), false)
    error_message = "notifications sns_topic_arn must be a standard SNS topic ARN (arn:<partition>:sns:<region>:<account>:<name>)."
  }

  validation {
    condition = var.notifications == null || try(length(var.notifications.events) >= 1 && alltrue([for e in var.notifications.events : contains([
      "BACKUP_JOB_STARTED", "BACKUP_JOB_COMPLETED", "BACKUP_JOB_SUCCESSFUL", "BACKUP_JOB_FAILED", "BACKUP_JOB_EXPIRED",
      "RESTORE_JOB_STARTED", "RESTORE_JOB_COMPLETED", "RESTORE_JOB_SUCCESSFUL", "RESTORE_JOB_FAILED",
      "COPY_JOB_STARTED", "COPY_JOB_SUCCESSFUL", "COPY_JOB_FAILED",
      "RECOVERY_POINT_MODIFIED", "BACKUP_PLAN_CREATED", "BACKUP_PLAN_MODIFIED",
      "S3_BACKUP_OBJECT_FAILED", "S3_RESTORE_OBJECT_FAILED", "CONTINUOUS_BACKUP_INTERRUPTED",
      "RECOVERY_POINT_INDEX_COMPLETED", "RECOVERY_POINT_INDEX_DELETED", "RECOVERY_POINT_INDEXING_FAILED",
      "EKS_RESTORE_OBJECT_FAILED", "EKS_RESTORE_OBJECT_SKIPPED", "EKS_BACKUP_OBJECT_FAILED",
      "ACCESS_POINT_AVAILABLE", "ACCESS_POINT_CREATION_FAILED", "ACCESS_POINT_DELETED",
      "ACCESS_POINT_DELETION_FAILED", "ACCESS_POINT_EXPIRED", "ACCESS_POINT_DISASSOCIATED",
    ], e)]), false)
    error_message = "notifications events must list at least one valid PutBackupVaultNotifications event, such as BACKUP_JOB_COMPLETED or COPY_JOB_FAILED."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "vault 所在的 region；`null`（預設）用 provider 的 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "vault 的 tag；`Name` 由 module 加上。"
}
