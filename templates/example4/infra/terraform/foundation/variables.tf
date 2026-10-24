variable "alarm_emails" {
  description = "訂閱告警 topic 的 email。每位收件人要先確認訂閱，才收得到告警。"
  type        = list(string)
  default     = []
}

variable "glue_catalog_encryption" {
  description = "帳號層的 Glue Data Catalog 加密，選填。`null` 不呼叫 module；物件才呼叫，`kms_key_arn` 沒給就用這個 stack 的共用 key。**每個帳號、每個 region 只能由一處設定**，同帳號的第二個專案要設 `null`；開啟後所有讀寫 catalog 的身分（包括其他專案）都要有該 key 的 `kms:Decrypt` 與 `kms:GenerateDataKey`。"
  type = object({
    kms_key_arn = optional(string)
  })
  default = null

  validation {
    condition     = var.glue_catalog_encryption == null ? true : (var.glue_catalog_encryption.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.glue_catalog_encryption.kms_key_arn)))
    error_message = "glue_catalog_encryption.kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and other services are not accepted."
  }
}
