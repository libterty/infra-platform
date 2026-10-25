variable "job_template_id" {
  type        = string
  description = "job template ID，1–64 字元，限英數字、`_`、`-`；也用在 `Name` tag。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.job_template_id))
    error_message = "job_template_id must be 1-64 chars of letters, digits, underscores and hyphens."
  }
}

variable "description" {
  type        = string
  description = "job template 的說明，1–2028 字元（AWS 必填）。"

  validation {
    condition     = length(var.description) >= 1 && length(var.description) <= 2028
    error_message = "description must be 1-2028 characters."
  }
}

variable "document" {
  type        = any
  default     = null
  description = "job document，用 HCL 物件寫，module 會 `jsonencode`（編碼後最多 32 KB）。跟 `document_source` 擇一。要讓裝置下載 S3 檔案時，網址寫成 `$${aws:iot:s3-presigned-url:https://s3.amazonaws.com/<bucket>/<key>}` 並設定 `presigned_url`。"

  validation {
    condition     = var.document == null || can(keys(var.document))
    error_message = "document must be an object; the module JSON-encodes it."
  }

  validation {
    condition     = var.document == null || try(length(jsonencode(var.document)) <= 32768, false)
    error_message = "document must be at most 32 KB once JSON-encoded."
  }
}

variable "document_source" {
  type        = string
  default     = null
  description = "放在 S3 的 job document 網址（`s3://<bucket>/<key>`）。跟 `document` 擇一。"

  validation {
    condition     = (var.document == null) != (var.document_source == null)
    error_message = "Exactly one of document and document_source must be set."
  }

  validation {
    condition     = var.document_source == null || can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/.+$", var.document_source))
    error_message = "document_source must be an S3 URL (s3://<bucket>/<key>)."
  }
}

variable "presigned_url" {
  type = object({
    role_arn       = string
    expires_in_sec = optional(number, 3600)
  })
  default     = null
  description = "job document 裡 S3 presigned URL 的設定；`null` 不設定。`role_arn` 是 IoT 用來簽網址的 role（要能 `s3:GetObject` 檔案）；`expires_in_sec` 是網址有效秒數，60–3600（預設 3600）。"

  validation {
    condition     = var.presigned_url == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", var.presigned_url.role_arn))
    error_message = "presigned_url.role_arn must be an IAM role ARN."
  }

  validation {
    condition     = var.presigned_url == null || try(var.presigned_url.expires_in_sec >= 60 && var.presigned_url.expires_in_sec <= 3600 && var.presigned_url.expires_in_sec == floor(var.presigned_url.expires_in_sec), false)
    error_message = "presigned_url.expires_in_sec must be a whole number between 60 and 3600."
  }
}

variable "rollout" {
  type = object({
    maximum_per_minute = optional(number)
    exponential = optional(object({
      base_rate_per_minute       = number
      increment_factor           = number
      number_of_succeeded_things = number
    }))
  })
  default     = null
  description = "發布速度；`null` 不限制。`maximum_per_minute`（每分鐘最多通知幾台，1–1000）與 `exponential` 擇一。`exponential` 的欄位：`base_rate_per_minute`（1–1000）、`increment_factor`（1.1–5）、`number_of_succeeded_things`（成功幾台後加速，至少 1）。"

  validation {
    condition     = var.rollout == null || try((var.rollout.maximum_per_minute == null) != (var.rollout.exponential == null), false)
    error_message = "rollout needs exactly one of maximum_per_minute and exponential."
  }

  validation {
    condition     = try(var.rollout.maximum_per_minute, null) == null || try(var.rollout.maximum_per_minute >= 1 && var.rollout.maximum_per_minute <= 1000 && var.rollout.maximum_per_minute == floor(var.rollout.maximum_per_minute), false)
    error_message = "rollout.maximum_per_minute must be a whole number between 1 and 1000."
  }

  validation {
    condition = try(var.rollout.exponential, null) == null || try(
      var.rollout.exponential.base_rate_per_minute >= 1 && var.rollout.exponential.base_rate_per_minute <= 1000 &&
      var.rollout.exponential.increment_factor >= 1.1 && var.rollout.exponential.increment_factor <= 5 &&
      var.rollout.exponential.number_of_succeeded_things >= 1,
      false
    )
    error_message = "rollout.exponential needs base_rate_per_minute 1-1000, increment_factor 1.1-5 and number_of_succeeded_things >= 1."
  }
}

variable "abort" {
  type = list(object({
    failure_type                  = string
    threshold_percentage          = number
    min_number_of_executed_things = number
  }))
  default     = []
  nullable    = false
  description = "中止條件，符合任一條就取消 job（`action` 固定 `CANCEL`）；空的就不設定。欄位：`failure_type`（`FAILED`、`REJECTED`、`TIMED_OUT`、`ALL`）、`threshold_percentage`（大於 0、最多 100）、`min_number_of_executed_things`（至少 1）。"

  validation {
    condition     = alltrue([for a in var.abort : contains(["FAILED", "REJECTED", "TIMED_OUT", "ALL"], a.failure_type)])
    error_message = "abort failure_type must be FAILED, REJECTED, TIMED_OUT or ALL."
  }

  validation {
    condition     = alltrue([for a in var.abort : a.threshold_percentage > 0 && a.threshold_percentage <= 100])
    error_message = "abort threshold_percentage must be greater than 0 and at most 100."
  }

  validation {
    condition     = alltrue([for a in var.abort : a.min_number_of_executed_things >= 1 && a.min_number_of_executed_things == floor(a.min_number_of_executed_things)])
    error_message = "abort min_number_of_executed_things must be a whole number >= 1."
  }
}

variable "timeout_minutes" {
  type        = number
  default     = null
  description = "每台裝置執行 job 的時間上限（分鐘，1–10080）；超過就標成 `TIMED_OUT`。`null` 不設上限。"

  validation {
    condition     = var.timeout_minutes == null || try(var.timeout_minutes >= 1 && var.timeout_minutes <= 10080 && var.timeout_minutes == floor(var.timeout_minutes), false)
    error_message = "timeout_minutes must be a whole number between 1 and 10080."
  }
}

variable "retry" {
  type = list(object({
    failure_type      = string
    number_of_retries = number
  }))
  default     = []
  nullable    = false
  description = "失敗重試條件；空的就不重試。欄位：`failure_type`（`FAILED`、`TIMED_OUT`、`ALL`）、`number_of_retries`（0–10）。"

  validation {
    condition     = alltrue([for r in var.retry : contains(["FAILED", "TIMED_OUT", "ALL"], r.failure_type)])
    error_message = "retry failure_type must be FAILED, TIMED_OUT or ALL."
  }

  validation {
    condition     = alltrue([for r in var.retry : r.number_of_retries >= 0 && r.number_of_retries <= 10 && r.number_of_retries == floor(r.number_of_retries)])
    error_message = "retry number_of_retries must be a whole number between 0 and 10."
  }
}

variable "maintenance_windows" {
  type = list(object({
    start_time       = string
    duration_minutes = number
  }))
  default     = []
  nullable    = false
  description = "只在這些時段發布 job；空的就不限制。欄位：`start_time`（cron 運算式，例如 `cron(0 18 ? * MON-FRI *)`，UTC）、`duration_minutes`（1–1430）。"

  validation {
    condition     = alltrue([for w in var.maintenance_windows : can(regex("^cron\\(.+\\)$", w.start_time))])
    error_message = "maintenance_windows start_time must be a cron(...) expression."
  }

  validation {
    condition     = alltrue([for w in var.maintenance_windows : w.duration_minutes >= 1 && w.duration_minutes <= 1430 && w.duration_minutes == floor(w.duration_minutes)])
    error_message = "maintenance_windows duration_minutes must be a whole number between 1 and 1430."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "job template 的 tag；`Name`（template ID）由 module 加上，module 轉成 `key`／`value` 的 set 傳給 resource。"
}
