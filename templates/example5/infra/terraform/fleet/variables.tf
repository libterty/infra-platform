variable "account_settings" {
  description = "帳號層的 IoT 設定（fleet indexing、logging、registry 事件），選填。`null` 不呼叫 module；物件才呼叫，`log_level` 是 IoT logging 的等級（`DEBUG`、`INFO`、`WARN`、`ERROR`、`DISABLED`，預設 `WARN`）。**每個帳號、每個 region 只能由一處設定**，同帳號的第二個專案要設 `null`。"
  type = object({
    log_level = optional(string, "WARN")
  })
  default = null

  validation {
    condition     = var.account_settings == null ? true : contains(["DEBUG", "INFO", "WARN", "ERROR", "DISABLED"], var.account_settings.log_level)
    error_message = "account_settings.log_level must be DEBUG, INFO, WARN, ERROR or DISABLED."
  }
}

variable "device_defender_audit" {
  description = "帳號層的 Device Defender audit 設定，選填。`null` 不設定（每週排程稽核與隔離用的 mitigation action 照樣建立）；物件（`{}`）就啟用排程稽核用到的 check，結果送到告警 topic。**每個帳號、每個 region 只能由一處設定**，同帳號的第二個專案要設 `null`。"
  type        = object({})
  default     = null
}

variable "ota_signing_certificate_arn" {
  description = "韌體簽章用的 code signing 憑證，在 Terraform 外匯入 ACM 後填 ARN（`arn:aws:acm:<region>:<account>:certificate/<id>`）。私鑰不經過 Terraform。"
  type        = string
}

variable "ota_rollout" {
  description = "OTA job 的發布設定：`maximum_per_minute` 是每分鐘最多通知幾台（1–1000），`abort_threshold_percentage` 是失敗比例超過多少就取消 job（大於 0、最多 100，至少執行 10 台後才判斷）。"
  type = object({
    maximum_per_minute         = number
    abort_threshold_percentage = number
  })

  validation {
    condition     = var.ota_rollout.maximum_per_minute >= 1 && var.ota_rollout.maximum_per_minute <= 1000 && floor(var.ota_rollout.maximum_per_minute) == var.ota_rollout.maximum_per_minute
    error_message = "ota_rollout.maximum_per_minute must be a whole number between 1 and 1000."
  }

  validation {
    condition     = var.ota_rollout.abort_threshold_percentage > 0 && var.ota_rollout.abort_threshold_percentage <= 100
    error_message = "ota_rollout.abort_threshold_percentage must be greater than 0 and at most 100."
  }
}
