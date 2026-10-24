variable "name" {
  type        = string
  description = "stream 名稱，1–128 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.name))
    error_message = "name must be 1-128 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "stream 加密用的客戶管理 KMS key ARN（symmetric），必填。`encryption_type` 固定是 `KMS`；key policy 要讓 producer 與 consumer 的 role 能用這把 key。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "mode" {
  type        = string
  default     = "ON_DEMAND"
  nullable    = false
  description = "容量模式：`ON_DEMAND`（自動擴縮，不能給 `shard_count`）或 `PROVISIONED`（必須給 `shard_count`）。"

  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.mode)
    error_message = "mode must be ON_DEMAND or PROVISIONED."
  }
}

variable "shard_count" {
  type        = number
  default     = null
  description = "shard 數量，至少 1。`mode = \"PROVISIONED\"` 時必填，`ON_DEMAND` 時必須是 `null`。"

  validation {
    condition     = var.mode == "PROVISIONED" ? (var.shard_count != null && try(var.shard_count >= 1 && var.shard_count == floor(var.shard_count), false)) : var.shard_count == null
    error_message = "shard_count must be a whole number >= 1 when mode is PROVISIONED, and must be null when mode is ON_DEMAND."
  }
}

variable "retention_hours" {
  type        = number
  default     = 24
  nullable    = false
  description = "資料保留時數，24–8760（預設 24）。超過 24 小時的保留期會另外計費。"

  validation {
    condition     = var.retention_hours >= 24 && var.retention_hours <= 8760 && var.retention_hours == floor(var.retention_hours)
    error_message = "retention_hours must be a whole number between 24 and 8760."
  }
}

variable "shard_level_metrics" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "要開的 shard 層級 CloudWatch 指標（`IncomingBytes`、`IncomingRecords`、`OutgoingBytes`、`OutgoingRecords`、`WriteProvisionedThroughputExceeded`、`ReadProvisionedThroughputExceeded`、`IteratorAgeMilliseconds`）。不收 `ALL`，要開就明列；空的就不開（額外計費）。"

  validation {
    condition = alltrue([for m in var.shard_level_metrics : contains([
      "IncomingBytes", "IncomingRecords", "OutgoingBytes", "OutgoingRecords",
      "WriteProvisionedThroughputExceeded", "ReadProvisionedThroughputExceeded", "IteratorAgeMilliseconds",
    ], m)])
    error_message = "shard_level_metrics accepts IncomingBytes, IncomingRecords, OutgoingBytes, OutgoingRecords, WriteProvisionedThroughputExceeded, ReadProvisionedThroughputExceeded and IteratorAgeMilliseconds; ALL is not accepted."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "stream 的 tag；`Name` 由 module 加上。"
}
