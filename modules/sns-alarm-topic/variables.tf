variable "name" {
  description = "topic 名稱，1–256 字元，限英數字、連字號、底線。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,256}$", var.name))
    error_message = "name must be 1-256 letters, digits, hyphens or underscores."
  }
}

variable "email_subscriptions" {
  description = "要訂閱告警的 email，每一筆都要是 email 格式。收件人確認訂閱之後才收得到告警。"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.email_subscriptions : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry must be an email address."
  }
}

variable "kms_master_key_id" {
  description = "客戶管理 KMS key 的 ARN，不可為 `alias/aws/sns`；key policy 要允許 `cloudwatch.amazonaws.com` 使用。`null` 不加密。"
  type        = string
  default     = null

  validation {
    condition     = var.kms_master_key_id == null ? true : var.kms_master_key_id != "alias/aws/sns"
    error_message = "alias/aws/sns cannot be used: CloudWatch alarms cannot publish to a topic encrypted with the AWS managed key."
  }
}

variable "tags" {
  description = "topic 的 tag；`Name` 由 module 加上。"
  type        = map(string)
  default     = {}
}
