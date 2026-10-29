variable "name" {
  type        = string
  description = "analyzer 名稱，1–255 字元，英文字母開頭，限英數字、`.`、`_`、`-`。"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_.-]{0,254}$", var.name))
    error_message = "name must be 1-255 chars, start with a letter and contain only letters, digits, dots, underscores or hyphens."
  }
}

variable "type" {
  type        = string
  default     = "ACCOUNT"
  nullable    = false
  description = "analyzer 類型：`ACCOUNT`（預設，本帳號的外部存取，免費）、`ORGANIZATION`（整個 organization 的外部存取，要在管理帳號或委派管理帳號建）、`ACCOUNT_UNUSED_ACCESS`、`ORGANIZATION_UNUSED_ACCESS`（未使用的權限，依分析的 role 與 user 數計費）。"

  validation {
    condition     = contains(["ACCOUNT", "ORGANIZATION", "ACCOUNT_UNUSED_ACCESS", "ORGANIZATION_UNUSED_ACCESS"], var.type)
    error_message = "type must be ACCOUNT, ORGANIZATION, ACCOUNT_UNUSED_ACCESS or ORGANIZATION_UNUSED_ACCESS."
  }
}

variable "unused_access_age_days" {
  type        = number
  default     = null
  description = "超過幾天沒用就算未使用的權限（1–365）。只有 `type` 是 `*_UNUSED_ACCESS` 時能給；`null` 用 AWS 預設。"

  validation {
    condition     = var.unused_access_age_days == null || endswith(var.type, "_UNUSED_ACCESS")
    error_message = "unused_access_age_days is only valid when type is ACCOUNT_UNUSED_ACCESS or ORGANIZATION_UNUSED_ACCESS."
  }

  validation {
    condition     = var.unused_access_age_days == null ? true : (var.unused_access_age_days >= 1 && var.unused_access_age_days <= 365)
    error_message = "unused_access_age_days must be between 1 and 365."
  }
}

variable "archive_rules" {
  type = map(list(object({
    criteria = string
    eq       = optional(list(string))
    neq      = optional(list(string))
    contains = optional(list(string))
    exists   = optional(bool)
  })))
  default     = {}
  nullable    = false
  description = "archive rule 名稱對應 filter 清單；符合全部 filter 的 finding 會自動封存。每個 filter 有 `criteria`（例如 `principal.AWS`、`resourceType`、`isPublic`）與至少一個比對：`eq`、`neq`、`contains`、`exists`。空的就不建 archive rule。"

  validation {
    condition     = alltrue([for filters in values(var.archive_rules) : length(filters) > 0])
    error_message = "Each archive rule needs at least one filter."
  }

  validation {
    condition = alltrue(flatten([for filters in values(var.archive_rules) : [
      for f in filters : f.eq != null || f.neq != null || f.contains != null || f.exists != null
    ]]))
    error_message = "Each archive rule filter needs at least one of eq, neq, contains or exists."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "analyzer 所在的 region；`null`（預設）用 provider 的 region。Access Analyzer 是 regional 服務，每個要分析的 region 各建一個。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "analyzer 的 tag；`Name` 由 module 加上。"
}
