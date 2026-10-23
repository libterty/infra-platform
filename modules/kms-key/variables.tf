variable "name" {
  type        = string
  description = "alias 名稱，不含 `alias/` 前綴。1–250 字元，限英數字、`/`、`_`、`-`，不可以 `aws/` 開頭。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]{1,250}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-250 chars of letters, digits, /, _ or -, and must not start with aws/."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "key 的說明。"
}

variable "deletion_window_in_days" {
  type        = number
  default     = 30
  description = "刪除 key 前的等待天數，7–30。"

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "administrator_arns" {
  type        = list(string)
  default     = []
  description = "額外的 key 管理者，限 IAM role 或 user ARN，不可含萬用字元。帳號 root 一律是管理者，不用列。"

  validation {
    condition     = alltrue([for a in var.administrator_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[^*]+$", a))])
    error_message = "administrator_arns must be IAM role or user ARNs; wildcards are not allowed."
  }
}

variable "service_principals" {
  type = map(object({
    actions = optional(list(string), ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default     = {}
  description = "服務 principal（例如 `logs.ap-northeast-1.amazonaws.com`，必須以 `.amazonaws.com` 結尾）對應它在這把 key 上的權限。欄位：`actions`（預設 `kms:Decrypt`、`kms:GenerateDataKey*`、`kms:DescribeKey`，不可給 `*` 或 `kms:*`）、`conditions`（`test`、`variable`、`values` 的清單，預設 `[]`）。"

  validation {
    condition     = alltrue([for k in keys(var.service_principals) : can(regex("^[a-z0-9.-]+\\.amazonaws\\.com$", k))])
    error_message = "Keys must be AWS service principals ending in .amazonaws.com; * is not allowed."
  }

  validation {
    condition     = alltrue(flatten([for v in values(var.service_principals) : [for a in v.actions : a != "*" && a != "kms:*"]]))
    error_message = "Service principals must not get * or kms:*."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "key 的 tag；`Name` 由 module 加上。"
}
