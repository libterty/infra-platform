variable "name" {
  type        = string
  description = "trail 名稱，3–128 字元，限英數字、`.`、`_`、`-`，開頭與結尾是英數字，不能有相鄰的 `.`、`_`、`-`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,126}[A-Za-z0-9]$", var.name)) && !can(regex("[._-]{2}", var.name))
    error_message = "name must be 3-128 chars of letters, digits, '.', '_' or '-', start and end with a letter or digit, and have no adjacent '.', '_' or '-'."
  }
}

variable "s3_bucket_name" {
  type        = string
  description = "存放 log 的 S3 bucket 名稱。bucket policy 要允許 `cloudtrail.amazonaws.com` 寫入（`s3-bucket` 0.6.0 的 `log_delivery` 含 `cloudtrail`）；module 不建 bucket。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_bucket_name))
    error_message = "s3_bucket_name must be a valid S3 bucket name."
  }
}

variable "s3_key_prefix" {
  type        = string
  default     = null
  description = "log 在 bucket 裡的 key prefix，最多 200 字元；`null`（預設）寫在 bucket 根目錄的 `AWSLogs/`。"

  validation {
    condition     = var.s3_key_prefix == null || (length(coalesce(var.s3_key_prefix, "x")) <= 200 && !startswith(coalesce(var.s3_key_prefix, "x"), "/") && !endswith(coalesce(var.s3_key_prefix, "x"), "/"))
    error_message = "s3_key_prefix must be at most 200 characters and must not start or end with '/'."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "加密 log 與 digest 檔的客戶管理 KMS key ARN（`key/<id>`，不收 alias），必填。key policy 要允許 `cloudtrail.amazonaws.com`，條件 `kms:EncryptionContext:aws:cloudtrail:arn`。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (key/<id>), not an alias."
  }
}

variable "is_multi_region_trail" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否記錄所有 region 的事件（預設 `true`）。organization trail 一定要 `true`。"
}

variable "is_organization_trail" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否為 organization trail（預設 `false`）。`true` 時只能在管理帳號或 CloudTrail 的委派管理帳號 apply，且 `is_multi_region_trail` 必須是 `true`。"

  validation {
    condition     = !var.is_organization_trail || var.is_multi_region_trail
    error_message = "is_organization_trail requires is_multi_region_trail = true."
  }
}

variable "cloudwatch_logs" {
  type = object({
    log_group_arn = string
    role_arn      = string
  })
  default     = null
  description = "同時把事件送到 CloudWatch Logs（選填）。`log_group_arn` 要以 `:*` 結尾（CloudTrail 要求 log stream 的萬用字元）；`role_arn` 是讓 `cloudtrail.amazonaws.com` 寫入 log group 的 role。`null`（預設）不送。"

  validation {
    condition     = var.cloudwatch_logs == null || can(regex("^arn:aws[a-z-]*:logs:[a-z0-9-]+:[0-9]{12}:log-group:[A-Za-z0-9_/.#-]{1,512}:\\*$", var.cloudwatch_logs.log_group_arn))
    error_message = "cloudwatch_logs.log_group_arn must be a CloudWatch Logs log group ARN ending in ':*'."
  }

  validation {
    condition     = var.cloudwatch_logs == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.cloudwatch_logs.role_arn))
    error_message = "cloudwatch_logs.role_arn must be an IAM role ARN."
  }
}

variable "advanced_event_selectors" {
  type = list(object({
    name = optional(string)
    field_selectors = list(object({
      field           = string
      equals          = optional(list(string))
      not_equals      = optional(list(string))
      starts_with     = optional(list(string))
      not_starts_with = optional(list(string))
      ends_with       = optional(list(string))
      not_ends_with   = optional(list(string))
    }))
  }))
  default     = null
  description = "advanced event selector（選填）。`null`（預設）只記 management event（第一份免費）。要記 data event 時給 selector，記得保留一個 `eventCategory = Management` 的 selector，否則 management event 會停掉；data event 依量計費。每個 selector 都要有 `eventCategory` 的 field selector。"

  validation {
    condition     = var.advanced_event_selectors == null || length(coalesce(var.advanced_event_selectors, [])) > 0
    error_message = "advanced_event_selectors must be null or a non-empty list."
  }

  validation {
    condition = var.advanced_event_selectors == null || alltrue([
      for s in coalesce(var.advanced_event_selectors, []) : contains([for f in s.field_selectors : f.field], "eventCategory")
    ])
    error_message = "Every advanced event selector needs an eventCategory field selector."
  }
}

variable "insight_types" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "要開的 CloudTrail Insights：`ApiCallRateInsight`、`ApiErrorRateInsight`（另外計費）。空的（預設）不開。"

  validation {
    condition     = alltrue([for t in var.insight_types : contains(["ApiCallRateInsight", "ApiErrorRateInsight"], t)])
    error_message = "insight_types may only contain ApiCallRateInsight and ApiErrorRateInsight."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "trail 的 home region；`null`（預設）用 provider 的 region。multi-region trail 在一個 region 建就涵蓋所有 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "trail 的 tag；`Name` 由 module 加上（值是 `name`）。"
}
