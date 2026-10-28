variable "api_image_tag" {
  description = "API Lambda 映像的 tag（不可用 `latest`）。換版就改這裡再 apply；apply 前映像要先推到 `containerimage` 的 repository。"
  type        = string
}

variable "api_reserved_concurrency" {
  description = "API Lambda 保留的並行數，也是被繞過 CloudFront 直接呼叫時的成本上限之一。"
  type        = number
}

variable "api_throttling" {
  description = "HTTP API `$default` stage 的 throttling：`rate_limit` 是每秒請求數，`burst_limit` 是瞬間上限。"
  type = object({
    rate_limit  = number
    burst_limit = number
  })
}

variable "origin_verify_header_name" {
  description = "CloudFront 回源時加的 origin verify header 名稱，要跟 `web` stack 的同名變數一致；值在 `foundation` 的 secret 裡。"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,64}$", var.origin_verify_header_name))
    error_message = "origin_verify_header_name must be 1-64 letters, digits or hyphens."
  }
}

variable "log_retention_days" {
  description = "API access log 與 Lambda log 的保留天數。"
  type        = number
}
