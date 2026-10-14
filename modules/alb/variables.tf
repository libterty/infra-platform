variable "name" {
  type        = string
  description = "ALB name, 2-32 characters."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 letters, digits or hyphens, not starting or ending with a hyphen nor starting with internal-."
  }
}

variable "internal" {
  type        = bool
  default     = false
  description = "true creates an internal ALB."
}

variable "subnet_ids" {
  type        = list(string)
  description = "public tier subnets (internal = true: app tier)."
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups created by the network stack."
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Give at least one security group (created by the network stack)."
  }
}

variable "certificate_arn" {
  type        = string
  default     = null
  description = "ACM certificate. null opens HTTP:80 only; the network stack must then narrow the ALB security group."
  validation {
    condition     = var.certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "additional_certificate_arns" {
  type        = set(string)
  default     = []
  description = "Extra certificates for SNI on the HTTPS listener; requires certificate_arn."
  validation {
    condition     = length(var.additional_certificate_arns) == 0 || var.certificate_arn != null
    error_message = "additional_certificate_arns needs certificate_arn: without a certificate there is no HTTPS listener."
  }
}

variable "idle_timeout" {
  type        = number
  default     = 60
  description = "Idle timeout in seconds."
  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be 1-4000 seconds."
  }
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "access_logs" {
  type = object({
    bucket = string           # SSE-S3 encrypted bucket name (not an ARN)
    prefix = optional(string) # null writes at the bucket root
  })
  default     = null
  description = "null disables access logs. The bucket must use SSE-S3: ALB log delivery does not support customer managed KMS."
}

variable "web_acl_arn" {
  type        = string
  default     = null
  description = "Regional WAFv2 Web ACL to associate; the module never creates one."
  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl_arn))
    error_message = "web_acl_arn must be a regional WAFv2 Web ACL ARN."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions. Required: an alarm nobody receives is not an alarm."
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "alarm_config" {
  type = object({
    elb_5xx_threshold = optional(number, 1) # sum of HTTPCode_ELB_5XX_Count within one period
    period            = optional(number, 60)
  })
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
