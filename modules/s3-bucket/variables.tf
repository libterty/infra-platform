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
  description = "null uses SSE-S3 (AES256). With vended_logs or vpc_flow_logs the key must be customer managed and its key policy must let delivery.logs.amazonaws.com use it."
}

variable "expiration_days" {
  type        = number
  default     = null
  description = "Days after which objects expire, 1-3650. null means 90. Must stay null when never_expire is true."

  validation {
    condition     = var.expiration_days == null ? true : (var.expiration_days >= 1 && var.expiration_days <= 3650)
    error_message = "expiration_days must be between 1 and 3650."
  }
}

variable "never_expire" {
  type        = bool
  default     = false
  nullable    = false
  description = "Keep objects until they are deleted explicitly: the lifecycle rule has no expiration. For content such as a knowledge base corpus; not for log buckets."

  validation {
    condition     = !(var.never_expire && var.expiration_days != null)
    error_message = "never_expire cannot be combined with expiration_days; leave expiration_days unset."
  }

  validation {
    condition     = !(var.never_expire && length(var.log_delivery) > 0)
    error_message = "never_expire cannot be combined with log_delivery; log buckets must expire."
  }
}

variable "log_delivery" {
  type        = set(string)
  default     = []
  description = "Log sources allowed to write: vended_logs (CloudWatch Logs vended delivery from this account, e.g. ALB, NLB or S3 access logs set up with log-delivery) and vpc_flow_logs."

  validation {
    condition     = alltrue([for v in var.log_delivery : contains(["vended_logs", "vpc_flow_logs"], v)])
    error_message = "log_delivery accepts vended_logs and vpc_flow_logs."
  }
}

variable "versioning" {
  type = object({
    noncurrent_expiration_days = optional(number, 30)
  })
  default     = null
  description = "null leaves versioning off. An object enables versioning, expires noncurrent versions after noncurrent_expiration_days (1-3650) and removes expired delete markers. Cannot be combined with log_delivery."

  validation {
    condition     = var.versioning == null ? true : (var.versioning.noncurrent_expiration_days >= 1 && var.versioning.noncurrent_expiration_days <= 3650)
    error_message = "versioning.noncurrent_expiration_days must be between 1 and 3650."
  }

  validation {
    condition     = var.versioning == null ? true : length(var.log_delivery) == 0
    error_message = "versioning cannot be combined with log_delivery; log buckets must not keep old versions."
  }
}

variable "expiration_prefix" {
  type        = string
  default     = null
  description = "Limit the expiration rule to keys under this prefix. null applies it to the whole bucket."

  validation {
    condition     = var.expiration_prefix == null ? true : (length(var.expiration_prefix) >= 1 && length(var.expiration_prefix) <= 1024)
    error_message = "expiration_prefix must be 1-1024 chars; use null to cover the whole bucket."
  }
}

variable "lambda_notifications" {
  type = map(object({
    function_arn  = string
    events        = optional(list(string), ["s3:ObjectCreated:*"])
    filter_prefix = optional(string)
    filter_suffix = optional(string)
  }))
  default     = {}
  description = "Notification id => Lambda function to invoke on bucket events. The caller must grant s3.amazonaws.com permission to invoke each function (with source_account and source_arn) before this is applied. Empty creates no notification resource."

  validation {
    condition     = alltrue([for n in values(var.lambda_notifications) : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+(:[A-Za-z0-9_$-]+)?$", n.function_arn))])
    error_message = "function_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }

  validation {
    condition     = alltrue([for n in values(var.lambda_notifications) : length(n.events) > 0])
    error_message = "Each lambda notification needs at least one event."
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
