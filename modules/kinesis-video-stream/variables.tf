variable "kms_key_arn" {
  type        = string
  description = "stream 加密用的客戶管理 KMS key ARN（symmetric），必填，所有 stream 共用。key policy 或寫入端、讀取端的 role 要有這把 key 的 `kms:GenerateDataKey`、`kms:Decrypt`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "streams" {
  type = map(object({
    retention_hours = optional(number, 24)
    media_type      = optional(string, "video/h264")
    device_name     = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Kinesis Video stream，key 是 stream 名稱（1–256 字元，限英數字、`_`、`-`、`.`）。`retention_hours` 是保留時數，0–87600（預設 24；0 表示不保留，只能即時消費）；`media_type` 是 MIME 類型（預設 `video/h264`）；`device_name` 是寫入這個 stream 的裝置名稱（選填，1–128 字元）。空的 map 不建任何 stream。"

  validation {
    condition     = alltrue([for name, _ in var.streams : can(regex("^[a-zA-Z0-9_.-]{1,256}$", name))])
    error_message = "stream names must be 1-256 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, s in var.streams : s.retention_hours != null && try(s.retention_hours >= 0 && s.retention_hours <= 87600 && s.retention_hours == floor(s.retention_hours), false)])
    error_message = "stream retention_hours must be a whole number between 0 and 87600."
  }

  validation {
    condition     = alltrue([for _, s in var.streams : s.media_type != null && can(regex("^[a-zA-Z0-9_.+-]+/[a-zA-Z0-9_.+-]+$", s.media_type)) && try(length(s.media_type) <= 128, false)])
    error_message = "stream media_type must be a MIME type such as video/h264 (at most 128 chars)."
  }

  validation {
    condition     = alltrue([for _, s in var.streams : s.device_name == null || can(regex("^[a-zA-Z0-9_.-]{1,128}$", s.device_name))])
    error_message = "stream device_name must be 1-128 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個 stream 的 tag；`Name` 由 module 加上（stream 名稱）。"
}
