variable "origin_verify_header_name" {
  description = "CloudFront 回源到 API 時加的 header 名稱，要跟 `api` stack 的同名變數一致。值由 `origin_verify_header_value` 給。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,64}$", var.origin_verify_header_name))
    error_message = "origin_verify_header_name must be 1-64 letters, digits or hyphens."
  }
}

variable "origin_verify_header_value" {
  description = "origin verify header 的值，跟 `foundation` 的 origin verify secret 裡的值一致。用 `TF_VAR_origin_verify_header_value` 傳入，不要寫進 tfvars。"
  type        = string
  sensitive   = true

  validation {
    condition     = nonsensitive(length(var.origin_verify_header_value) >= 16)
    error_message = "origin_verify_header_value must be at least 16 characters."
  }
}

variable "waf_rate_limit_per_5min" {
  description = "每個來源 IP 每 5 分鐘的請求上限，超過就被 WAF 擋下。"
  type        = number
}

variable "log_retention_days" {
  description = "CloudFront log 與 WAF log 的保留天數。"
  type        = number
}
