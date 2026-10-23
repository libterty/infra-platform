variable "name" {
  type        = string
  description = "Memory 的完整名稱。字母開頭，只能用字母、數字、`_`，最多 48 字元。"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", var.name))
    error_message = "name must start with a letter and use letters, digits or underscores, at most 48 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Memory 的說明。"
}

variable "event_expiry_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "短期事件保留天數，7–365 的整數。改了只影響之後寫入的事件。"

  # The aws provider rejects values below 7 at plan time, even though the API documents 3.
  validation {
    condition     = var.event_expiry_days >= 7 && var.event_expiry_days <= 365 && floor(var.event_expiry_days) == var.event_expiry_days
    error_message = "event_expiry_days must be a whole number between 7 and 365."
  }
}

variable "strategies" {
  type = map(object({
    type        = string
    namespaces  = list(string)
    description = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "內建的長期記憶 strategy，key 是 strategy 名稱（規則同 `name`）；空的時候只有短期記憶。欄位：`type`（必填，`SEMANTIC`、`SUMMARIZATION` 或 `USER_PREFERENCE`）、`namespaces`（必填，至少一個，每個以 `/` 開頭的樣板，例如 `/actors/{actorId}/facts`）、`description`（選填）。"

  validation {
    condition     = alltrue([for k in keys(var.strategies) : can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,47}$", k))])
    error_message = "Each strategies key is the strategy name: start with a letter, letters, digits or underscores, at most 48 chars."
  }

  validation {
    condition     = alltrue([for s in values(var.strategies) : contains(["SEMANTIC", "SUMMARIZATION", "USER_PREFERENCE"], s.type)])
    error_message = "strategy type must be SEMANTIC, SUMMARIZATION or USER_PREFERENCE; CUSTOM and self-managed strategies are not supported."
  }

  validation {
    condition     = alltrue([for s in values(var.strategies) : length(s.namespaces) > 0 && alltrue([for n in s.namespaces : startswith(n, "/")])])
    error_message = "Each strategy needs at least one namespace and every namespace must start with /."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Memory 用的自管 KMS key ARN（`key/<uuid>` 或 `key/mrk-<32 碼>`，不收 alias 與 `*`），key policy 要允許 AgentCore 使用。`null` 時用 AWS 擁有的 key。"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<uuid>), not an alias or a wildcard."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "套用到 Memory 的 tag，另外自動加 `Name`；strategy 沒有 tag。"
}
