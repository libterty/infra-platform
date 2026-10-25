variable "name" {
  type        = string
  description = "主 queue 的名稱，1–71 字元，限英數字、`_`、`-`，不含 `.fifo`。DLQ 的名稱是 `<name>-dlq`；`fifo = true` 時兩個名稱都由 module 加上 `.fifo`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,71}$", var.name))
    error_message = "name must be 1-71 chars of letters, digits, underscores or hyphens, without the .fifo suffix (the module adds -dlq and .fifo)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "主 queue 與 DLQ 加密用的客戶管理 KMS key ARN（symmetric），必填，不提供 SQS 管理的 SSE。key policy 要讓傳送端有 `kms:GenerateDataKey`、consumer 有 `kms:Decrypt`；EventBridge 寫入時 key policy 要允許 `events.amazonaws.com`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "fifo" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否建 FIFO queue（預設 `false`）。`true` 時主 queue 與 DLQ 都是 FIFO、開 content-based deduplication，名稱加上 `.fifo`。"
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 30
  nullable    = false
  description = "主 queue 的 visibility timeout 秒數，0–43200（預設 30）。要比 consumer 處理一則訊息的時間長。"

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200 && var.visibility_timeout_seconds == floor(var.visibility_timeout_seconds)
    error_message = "visibility_timeout_seconds must be a whole number between 0 and 43200."
  }
}

variable "message_retention_seconds" {
  type        = number
  default     = 345600
  nullable    = false
  description = "主 queue 的訊息保留秒數，60–1209600（預設 345600，4 天）。"

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600 && var.message_retention_seconds == floor(var.message_retention_seconds)
    error_message = "message_retention_seconds must be a whole number between 60 and 1209600."
  }
}

variable "max_receive_count" {
  type        = number
  default     = 5
  nullable    = false
  description = "訊息被收幾次還沒刪除就移到 DLQ，1–1000（預設 5）。"

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000 && var.max_receive_count == floor(var.max_receive_count)
    error_message = "max_receive_count must be a whole number between 1 and 1000."
  }
}

variable "dlq_retention_seconds" {
  type        = number
  default     = 1209600
  nullable    = false
  description = "DLQ 的訊息保留秒數，60–1209600（預設 1209600，14 天）。標準 queue 的保留期從訊息進主 queue 時起算，DLQ 的保留期要比主 queue 長。"

  validation {
    condition     = var.dlq_retention_seconds >= 60 && var.dlq_retention_seconds <= 1209600 && var.dlq_retention_seconds == floor(var.dlq_retention_seconds)
    error_message = "dlq_retention_seconds must be a whole number between 60 and 1209600."
  }
}

variable "allowed_source_arns" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "可以送訊息到主 queue 的 EventBridge rule ARN（`arn:aws:events:...:rule/...`）。有值就建 queue policy，只允許 `events.amazonaws.com` 在 `aws:SourceArn` 符合時 `sqs:SendMessage`；空的就不建 queue policy（IoT rule 等用 role 寫入的來源不需要）。"

  validation {
    condition     = alltrue([for a in var.allowed_source_arns : can(regex("^arn:aws[a-z-]*:events:[a-z0-9-]+:[0-9]{12}:rule/.+$", a))])
    error_message = "allowed_source_arns must be EventBridge rule ARNs (arn:<partition>:events:<region>:<account>:rule/<name>)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "主 queue 與 DLQ 的 tag；`Name` 由 module 加上。"
}
