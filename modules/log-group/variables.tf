variable "name" {
  type        = string
  description = "Log group name."
  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-512 chars of letters, digits, _ . / # or -, and must not start with aws/."
  }
}

variable "retention_days" {
  type        = number
  default     = 30
  description = "Retention in days. Never-expire (0) is not accepted."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_days)
    error_message = "retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key. Its key policy must allow logs.<region>.amazonaws.com."
}

variable "subscription" {
  type = object({
    destination_arn = string
    filter_pattern  = optional(string, "")
    role_arn        = optional(string)
  })
  default     = null
  description = "Optional subscription filter. destination_arn is a Lambda, Kinesis, Firehose or logs destination; an empty filter_pattern forwards every event; role_arn is required for Kinesis and Firehose."
  validation {
    condition = var.subscription == null ? true : (
      can(regex("^arn:aws[a-z-]*:(lambda|kinesis|firehose|logs):", var.subscription.destination_arn)) &&
      (can(regex(":(kinesis|firehose):", var.subscription.destination_arn)) ? var.subscription.role_arn != null : true)
    )
    error_message = "destination_arn must be a Lambda, Kinesis, Firehose or logs destination ARN; Kinesis and Firehose need role_arn."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the log group. Name is added by the module."
}
