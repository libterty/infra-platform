variable "indexing_percentage" {
  type        = number
  default     = 1
  description = "建索引（trace summary）的 span 比例，0–100。`1` 免費，調高另外計費。"

  validation {
    condition     = var.indexing_percentage >= 0 && var.indexing_percentage <= 100
    error_message = "indexing_percentage must be between 0 and 100."
  }
}

variable "resource_policy_name" {
  type        = string
  default     = "xray-transaction-search"
  description = "讓 X-Ray 寫入 span 的 CloudWatch Logs resource policy 名稱，同帳號、同 region 內必須唯一，不可為空白。"

  validation {
    condition     = length(trimspace(var.resource_policy_name)) > 0
    error_message = "resource_policy_name must not be empty."
  }
}
