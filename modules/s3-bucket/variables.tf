variable "name" {
  type        = string
  description = "bucket 名稱，3–63 字元，小寫英數字與連字號，不可含 `.` 或 `--`。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-63 chars of lowercase letters, digits or hyphens; dots are not allowed (they break TLS virtual-host addressing)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "`null` 用 SSE-S3（`AES256`）；有給就用 SSE-KMS。`log_delivery` 含 `vended_logs` 或 `vpc_flow_logs` 時必須是客戶管理的 key，而且 key policy 要允許 `delivery.logs.amazonaws.com` 使用。"
}

variable "expiration_days" {
  type        = number
  default     = null
  description = "物件過期天數，1–3650；`null` 當成 90。`never_expire = true` 時必須是 `null`。"

  validation {
    condition     = var.expiration_days == null ? true : (var.expiration_days >= 1 && var.expiration_days <= 3650)
    error_message = "expiration_days must be between 1 and 3650."
  }
}

variable "never_expire" {
  type        = bool
  default     = false
  nullable    = false
  description = "不設過期，物件保留到被明確刪除，lifecycle rule 沒有 expiration。給內容 bucket（例如 Knowledge Base 語料），不要用在 log bucket；與非空的 `log_delivery` 互斥。"

  validation {
    condition     = !(var.never_expire && var.expiration_days != null)
    error_message = "never_expire cannot be combined with expiration_days; leave expiration_days unset."
  }

  validation {
    condition     = !(var.never_expire && length(var.log_delivery) > 0)
    error_message = "never_expire cannot be combined with log_delivery; log buckets must expire."
  }
}

variable "log_delivery" {
  type        = set(string)
  default     = []
  description = "允許寫入的 log 來源：`vended_logs`（本帳號 CloudWatch Logs 的 vended delivery，例如用 `log-delivery` 設定的 ALB、NLB、S3 access log）、`vpc_flow_logs`。"

  validation {
    condition     = alltrue([for v in var.log_delivery : contains(["vended_logs", "vpc_flow_logs"], v)])
    error_message = "log_delivery accepts vended_logs and vpc_flow_logs."
  }
}

variable "versioning" {
  type = object({
    noncurrent_expiration_days = optional(number, 30)
  })
  default     = null
  description = "`null` 不開 versioning。給物件就開 versioning：舊版本在 `noncurrent_expiration_days`（1–3650，預設 30）天後過期，並清掉過期的 delete marker。與非空的 `log_delivery` 互斥。"

  validation {
    condition     = var.versioning == null ? true : (var.versioning.noncurrent_expiration_days >= 1 && var.versioning.noncurrent_expiration_days <= 3650)
    error_message = "versioning.noncurrent_expiration_days must be between 1 and 3650."
  }

  validation {
    condition     = var.versioning == null ? true : length(var.log_delivery) == 0
    error_message = "versioning cannot be combined with log_delivery; log buckets must not keep old versions."
  }
}

variable "expiration_prefix" {
  type        = string
  default     = null
  description = "目前版本的過期規則只套用在這個 prefix 底下（1–1024 字元）；`null` 套用整個 bucket。"

  validation {
    condition     = var.expiration_prefix == null ? true : (length(var.expiration_prefix) >= 1 && length(var.expiration_prefix) <= 1024)
    error_message = "expiration_prefix must be 1-1024 chars; use null to cover the whole bucket."
  }
}

variable "transitions" {
  type = list(object({
    days          = number
    storage_class = string
  }))
  default     = []
  nullable    = false
  description = "目前版本的 lifecycle 分層，依序列出 `days`（物件建立後第幾天，至少 1，必須嚴格遞增）與 `storage_class`（`STANDARD_IA`、`ONEZONE_IA`、`INTELLIGENT_TIERING`、`GLACIER_IR`、`GLACIER`、`DEEP_ARCHIVE`）。每個 `days` 都要小於過期天數（沒給 `expiration_days` 時是 90）；`never_expire = true` 時不比較。跟過期規則共用 `expiration_prefix`。空的就不分層。"

  validation {
    condition     = alltrue([for t in var.transitions : contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)])
    error_message = "transitions storage_class must be one of STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER, DEEP_ARCHIVE."
  }

  validation {
    condition     = alltrue([for t in var.transitions : t.days >= 1])
    error_message = "transitions days must be at least 1."
  }

  validation {
    condition     = alltrue([for i, t in var.transitions : i == 0 ? true : t.days > var.transitions[i - 1].days])
    error_message = "transitions days must be strictly increasing."
  }

  validation {
    condition     = var.never_expire || alltrue([for t in var.transitions : t.days < coalesce(var.expiration_days, 90)])
    error_message = "Every transitions days must be less than the expiration days (90 when expiration_days is not set)."
  }
}

variable "eventbridge" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否把這個 bucket 的所有 S3 事件送到本帳號 default event bus（`aws.s3`，例如 `Object Created`）。為 `true` 時建立 notification，可以跟 `lambda_notifications` 並存；呼叫端另外建 EventBridge rule 與 target。"
}

variable "lambda_notifications" {
  type = map(object({
    function_arn  = string
    events        = optional(list(string), ["s3:ObjectCreated:*"])
    filter_prefix = optional(string)
    filter_suffix = optional(string)
  }))
  default     = {}
  description = "notification id 對應 bucket 事件要呼叫的 Lambda。欄位：`function_arn`（必須是 Lambda function ARN）、`events`（至少一個，預設 `s3:ObjectCreated:*`）、`filter_prefix`、`filter_suffix`。呼叫端要先給 `s3.amazonaws.com` 呼叫每個 function 的權限（帶 `source_account` 與 `source_arn`）再 apply。空的就不建 notification。"

  validation {
    condition     = alltrue([for n in values(var.lambda_notifications) : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+(:[A-Za-z0-9_$-]+)?$", n.function_arn))])
    error_message = "function_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }

  validation {
    condition     = alltrue([for n in values(var.lambda_notifications) : length(n.events) > 0])
    error_message = "Each lambda notification needs at least one event."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "是否允許刪除非空的 bucket。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "bucket 的 tag；`Name` 由 module 加上。"
}
