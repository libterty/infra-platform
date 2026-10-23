variable "name" {
  type        = string
  description = "完整的 repository 名稱，2–256 字元。小寫字母與數字，以 `.`、`_`、`-` 分隔，可用 `/` 分層。"
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 256 && can(regex("^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$", var.name))
    error_message = "name must be a valid ECR repository name (lowercase, digits, . _ - and / separators)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "映像加密用的客戶管理金鑰；`null` 用 `AES256`。既有 repository 改這個值會重建 repository，裡面的映像會被刪掉。"
}

variable "lifecycle_rules" {
  type = object({
    untagged_expire_days = optional(number, 7)
    keep_count           = optional(number, 50)
  })
  default     = {}
  description = "映像的保留規則。欄位：`untagged_expire_days`（未加 tag 的映像幾天後刪除，預設 7）、`keep_count`（最多保留幾個映像，預設 50），兩個都至少為 1。"
  validation {
    condition     = var.lifecycle_rules.untagged_expire_days >= 1 && var.lifecycle_rules.keep_count >= 1
    error_message = "untagged_expire_days and keep_count must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "額外的 tag；module 只另外加 `Name`。"
}
