variable "name" {
  type        = string
  description = "secret 的名稱，1–512 字元，限英數字與 `/_+=.@-`。以 `-` 加 6 個字元結尾的名稱（例如 `-master`）可以用，但引用時要用完整 ARN，不要用名稱或部分 ARN。"

  validation {
    condition     = can(regex("^[A-Za-z0-9/_+=.@-]{1,512}$", var.name))
    error_message = "name must be 1-512 chars of letters, digits or /_+=.@-."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "secret 的說明（預設 `null`）。建議寫明值由誰、在哪裡寫入。"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "加密 secret 的客戶管理 KMS key ARN（symmetric）。`null`（預設）時用 AWS 管理的 `aws/secretsmanager`。只收 key ARN，不收 alias。"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "recovery_window_in_days" {
  type        = number
  default     = 7
  nullable    = false
  description = "刪除 secret 後可以還原的天數，7–30（預設 7）。不收 `0`，避免刪除後立刻消失、名稱也被釋放。"

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30 && var.recovery_window_in_days == floor(var.recovery_window_in_days)
    error_message = "recovery_window_in_days must be a whole number between 7 and 30; 0 (delete at once) is not accepted."
  }
}

variable "policy_statements" {
  type = list(object({
    sid    = string
    effect = string
    principals = object({
      type        = string
      identifiers = list(string)
    })
    actions = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default     = []
  nullable    = false
  description = "resource policy 的 statement。空的（預設）就不建 policy，存取完全由 IAM 決定。欄位：`sid`（英數字，不可重複）、`effect`（`Allow` 或 `Deny`）、`principals`（`type` 是 `AWS` 或 `Service`，`identifiers` 至少一個）、`actions`（`secretsmanager:` 開頭）、`conditions`（`test`、`variable`、`values` 的清單，預設 `[]`）。`Resource` 固定是這個 secret。`Allow` 不可給 `secretsmanager:*`；`identifiers` 含 `*` 的 `Allow` 一定要有 condition。policy 一律開 `block_public_policy`。"

  validation {
    condition     = alltrue([for s in var.policy_statements : can(regex("^[A-Za-z0-9]{1,100}$", s.sid))]) && length(distinct([for s in var.policy_statements : s.sid])) == length(var.policy_statements)
    error_message = "Each sid must be 1-100 letters or digits and unique within policy_statements."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : contains(["Allow", "Deny"], s.effect)])
    error_message = "effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : contains(["AWS", "Service"], s.principals.type) && length(s.principals.identifiers) > 0])
    error_message = "principals.type must be AWS or Service, and principals.identifiers must not be empty."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : length(s.actions) > 0 && alltrue([for a in s.actions : can(regex("^secretsmanager:[A-Za-z*]+$", a))])])
    error_message = "actions must not be empty and every action must start with secretsmanager:."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : s.effect != "Allow" || !contains(s.actions, "secretsmanager:*")])
    error_message = "An Allow statement must not grant secretsmanager:*; list the actions that are needed."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : s.effect != "Allow" || !contains(s.principals.identifiers, "*") || length(s.conditions) > 0])
    error_message = "An Allow statement with principal * must have at least one condition, or it grants access to everyone."
  }
}

variable "rotation" {
  type = object({
    lambda_arn               = string
    automatically_after_days = optional(number)
    schedule_expression      = optional(string)
    duration                 = optional(string)
    rotate_immediately       = optional(bool, false)
  })
  default     = null
  description = "輪替設定。`null`（預設）就不設定輪替。欄位：`lambda_arn`（輪替 Lambda 的 function ARN）、`automatically_after_days`（1–1000）或 `schedule_expression`（`rate(...)` 或 `cron(...)`）擇一、`duration`（輪替視窗，`1h`–`24h`，選填）、`rotate_immediately`（設定後是否立刻輪替一次，預設 `false`）。Lambda 的 resource policy 要允許 `secretsmanager.amazonaws.com`（`lambda-function` 的 `permissions`）。"

  validation {
    condition     = var.rotation == null ? true : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}(:[A-Za-z0-9_$-]{1,128})?$", var.rotation.lambda_arn))
    error_message = "rotation.lambda_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>)."
  }

  validation {
    condition     = var.rotation == null ? true : (var.rotation.automatically_after_days == null) != (var.rotation.schedule_expression == null)
    error_message = "rotation needs exactly one of automatically_after_days and schedule_expression."
  }

  validation {
    condition     = var.rotation == null ? true : var.rotation.automatically_after_days == null ? true : var.rotation.automatically_after_days >= 1 && var.rotation.automatically_after_days <= 1000 && var.rotation.automatically_after_days == floor(var.rotation.automatically_after_days)
    error_message = "rotation.automatically_after_days must be a whole number between 1 and 1000."
  }

  validation {
    condition     = var.rotation == null ? true : var.rotation.schedule_expression == null ? true : can(regex("^(rate|cron)\\(.+\\)$", var.rotation.schedule_expression))
    error_message = "rotation.schedule_expression must be rate(...) or cron(...)."
  }

  validation {
    condition     = var.rotation == null ? true : var.rotation.duration == null ? true : can(regex("^([1-9]|1[0-9]|2[0-4])h$", var.rotation.duration))
    error_message = "rotation.duration must be between 1h and 24h, for example 3h."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "secret 的 tag；`Name` 由 module 加上。"
}
