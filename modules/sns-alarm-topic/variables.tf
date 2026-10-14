variable "name" {
  description = "Topic name, 1-256 letters, digits, hyphens or underscores."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,256}$", var.name))
    error_message = "name must be 1-256 letters, digits, hyphens or underscores."
  }
}

variable "email_subscriptions" {
  description = "Email addresses to subscribe. Each recipient must confirm the subscription before alarms arrive."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.email_subscriptions : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry must be an email address."
  }
}

variable "kms_master_key_id" {
  description = "Customer managed KMS key ARN; its key policy must let cloudwatch.amazonaws.com use it. null leaves the topic unencrypted."
  type        = string
  default     = null

  validation {
    condition     = var.kms_master_key_id == null ? true : var.kms_master_key_id != "alias/aws/sns"
    error_message = "alias/aws/sns cannot be used: CloudWatch alarms cannot publish to a topic encrypted with the AWS managed key."
  }
}

variable "tags" {
  description = "Tags for the topic; Name is added automatically."
  type        = map(string)
  default     = {}
}
