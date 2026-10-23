variable "indexing_percentage" {
  type        = number
  default     = 1
  description = "Percentage of ingested spans indexed as trace summaries. 1 is free; higher values are billed."

  validation {
    condition     = var.indexing_percentage >= 0 && var.indexing_percentage <= 100
    error_message = "indexing_percentage must be between 0 and 100."
  }
}

variable "resource_policy_name" {
  type        = string
  default     = "xray-transaction-search"
  description = "Name of the CloudWatch Logs resource policy that lets X-Ray write spans. Unique per account and region."

  validation {
    condition     = length(trimspace(var.resource_policy_name)) > 0
    error_message = "resource_policy_name must not be empty."
  }
}
