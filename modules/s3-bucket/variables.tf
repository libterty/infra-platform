variable "name" {
  type        = string
  description = "Bucket name."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-63 chars of lowercase letters, digits or hyphens; dots are not allowed (they break TLS virtual-host addressing)."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "null uses SSE-S3 (AES256). ALB access log buckets must stay on SSE-S3."

  validation {
    condition     = var.kms_key_arn == null || !contains(var.log_delivery, "alb_access_logs")
    error_message = "ALB access log delivery does not support SSE-KMS; logs would be dropped silently. Leave kms_key_arn null for buckets that receive alb_access_logs."
  }
}

variable "expiration_days" {
  type        = number
  default     = 90
  description = "Days after which objects expire."

  validation {
    condition     = var.expiration_days >= 1 && var.expiration_days <= 3650
    error_message = "expiration_days must be between 1 and 3650."
  }
}

variable "log_delivery" {
  type        = set(string)
  default     = []
  description = "Log sources allowed to write: alb_access_logs, vpc_flow_logs."

  validation {
    condition     = alltrue([for v in var.log_delivery : contains(["alb_access_logs", "vpc_flow_logs"], v)])
    error_message = "log_delivery accepts alb_access_logs and vpc_flow_logs."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow destroying a non-empty bucket."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the bucket. Name is added by the module."
}
