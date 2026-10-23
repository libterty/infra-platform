variable "name" {
  type        = string
  description = "cluster 名稱，2–63 字元，限小寫英數字與連字號，字母開頭。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be 2-63 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights 等級：`disabled`、`enabled`、`enhanced`。"

  validation {
    condition     = contains(["disabled", "enabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be disabled, enabled or enhanced."
  }
}

variable "default_capacity_provider_strategy" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default     = [{ capacity_provider = "FARGATE" }]
  description = "沒指定策略的 service 使用的預設策略；`FARGATE` 與 `FARGATE_SPOT` 一律都會掛到 cluster。欄位：`capacity_provider`（只能是 `FARGATE` 或 `FARGATE_SPOT`）、`weight`（預設 `1`）、`base`（預設 `0`，最多一個 provider 可以 `base > 0`）。不可為空清單。"

  validation {
    condition     = length(var.default_capacity_provider_strategy) > 0 && alltrue([for s in var.default_capacity_provider_strategy : contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider)])
    error_message = "Strategy must name FARGATE or FARGATE_SPOT only."
  }

  validation {
    condition     = length([for s in var.default_capacity_provider_strategy : s if s.base > 0]) <= 1
    error_message = "Only one capacity provider may set base > 0."
  }
}

variable "service_connect_namespace" {
  type        = string
  default     = null
  description = "Service Connect 用的 Cloud Map HTTP namespace 名稱；`null` 時不建。"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Container Insights performance log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "performance log group 的 KMS key ARN；`null` 時用預設加密。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個資源的 tag；`Name` 由 module 加上。"
}
