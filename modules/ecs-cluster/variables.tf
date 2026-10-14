variable "name" {
  type        = string
  description = "Cluster name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.name))
    error_message = "name must be 2-63 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "container_insights" {
  type        = string
  default     = "enhanced"
  description = "Container Insights level: disabled, enabled or enhanced."

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
  description = "Default strategy for services that set none. Both FARGATE and FARGATE_SPOT are always attached to the cluster."

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
  description = "Cloud Map HTTP namespace name for Service Connect; null creates none."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the Container Insights performance log group."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for the performance log group; null uses the default encryption."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource; Name is added by the module."
}
