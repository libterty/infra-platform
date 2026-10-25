variable "name" {
  type        = string
  description = "pipeline 名稱，1–256 字元，限英數字與 `-`，開頭結尾是英數字。"

  validation {
    condition     = length(var.name) <= 256 && can(regex("^[a-zA-Z0-9](-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be 1-256 chars of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "definition" {
  type        = string
  description = "pipeline definition 的 JSON 字串（SageMaker Python SDK 的 `pipeline.definition()` 匯出後 commit，範本用 `file()` 讀），要有 `Version` 與至少一個 `Steps`。module 原樣傳給 SageMaker，不從 S3 讀。"

  validation {
    condition     = can(jsondecode(var.definition).Version)
    error_message = "definition must be a JSON object with a Version field."
  }

  validation {
    condition     = try(length(jsondecode(var.definition).Steps) >= 1 && can(jsondecode(var.definition).Steps[0]), false)
    error_message = "definition must be a JSON object with a non-empty Steps list."
  }
}

variable "role_arn" {
  type        = string
  description = "pipeline 執行用的 IAM role ARN（module 不建 role）。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "display_name" {
  type        = string
  default     = null
  description = "在 SageMaker Studio 顯示的名稱，規則同 `name`；`null` 就用 `name`。"

  validation {
    condition     = var.display_name == null || (length(coalesce(var.display_name, " ")) <= 256 && can(regex("^[a-zA-Z0-9](-*[a-zA-Z0-9])*$", coalesce(var.display_name, " "))))
    error_message = "display_name must be 1-256 chars of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "pipeline 的說明，最多 3072 字元；`null` 不設。"

  validation {
    condition     = var.description == null || length(coalesce(var.description, " ")) <= 3072
    error_message = "description must be at most 3072 characters."
  }
}

variable "max_parallel_steps" {
  type        = number
  default     = null
  description = "同一次執行最多同時跑幾個 step，至少 1；`null` 不設（用 SageMaker 的預設）。"

  validation {
    condition     = var.max_parallel_steps == null || try(var.max_parallel_steps >= 1 && var.max_parallel_steps == floor(var.max_parallel_steps), false)
    error_message = "max_parallel_steps must be a whole number >= 1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "pipeline 的 tag；`Name` 由 module 加上。"
}
