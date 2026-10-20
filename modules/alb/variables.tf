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

variable "web_acl" {
  type = object({
    arn = string
  })
  default     = null
  description = "Regional WAFv2 Web ACL to associate; the module never creates one. Use this, not web_acl_arn, when the ARN is not known at plan time (the Web ACL is created in the same configuration): whether the object is null is always known, even when arn is not."
  validation {
    condition     = var.web_acl == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl.arn))
    error_message = "web_acl.arn must be a regional WAFv2 Web ACL ARN."
  }
  validation {
    condition     = var.web_acl == null || var.web_acl_arn == null
    error_message = "Set either web_acl or web_acl_arn, not both."
  }
}

variable "web_acl_arn" {
  type        = string
  default     = null
  description = "Regional WAFv2 Web ACL to associate. Only for ARNs known at plan time; it fails with \"Invalid count argument\" when the Web ACL is created in the same configuration. Use web_acl instead. Kept for existing callers and planned for removal."
  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.web_acl_arn))
    error_message = "web_acl_arn must be a regional WAFv2 Web ACL ARN."
  }
}

variable "vpc_id" {
  type        = string
  default     = null
  description = "VPC of the target groups. Required when target_groups is non-empty."
  validation {
    condition     = length(var.target_groups) == 0 || var.vpc_id != null
    error_message = "vpc_id is required when target_groups is non-empty."
  }
}

variable "target_groups" {
  type = map(object({
    port                 = number
    protocol_version     = optional(string, "HTTP1")
    deregistration_delay = optional(number, 300)
    health_check = optional(object({
      path                = optional(string, "/health")
      matcher             = optional(string, "200")
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))
  default     = {}
  description = "Key => IP target group named <name>-<key>. Changing a port replaces the target group, which fails while a rule still uses it; add a new key and move the rule instead."
  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", "${var.name}-${k}"))])
    error_message = "<name>-<key> must be 1-32 letters, digits or hyphens, not starting or ending with a hyphen."
  }
}

variable "listener_rules" {
  type = map(object({
    priority              = number
    target_group          = string
    path_patterns         = optional(list(string), [])
    host_headers          = optional(list(string), [])
    require_origin_verify = optional(bool, false)
  }))
  default     = {}
  description = "Key => forward rule on the HTTPS listener (the HTTP listener when there is no certificate). Needs at least one path pattern or host header. require_origin_verify = true (opt-in) adds the origin verify header condition and needs origin_verify_header_name."
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : contains(keys(var.target_groups), r.target_group)])
    error_message = "Every rule target_group must be a key of target_groups."
  }
  validation {
    condition     = length(distinct([for r in values(var.listener_rules) : r.priority])) == length(var.listener_rules)
    error_message = "Rule priorities must be unique."
  }
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : length(r.path_patterns) + length(r.host_headers) > 0])
    error_message = "Every rule needs at least one path pattern or host header."
  }
  validation {
    condition     = alltrue([for r in values(var.listener_rules) : !r.require_origin_verify || var.origin_verify_header_name != null])
    error_message = "A rule with require_origin_verify = true needs origin_verify_header_name and origin_verify_header_value."
  }
  # ALB allows five condition values per rule; the origin verify header takes one of them.
  validation {
    condition = alltrue([
      for r in values(var.listener_rules) :
      length(r.path_patterns) + length(r.host_headers) + (r.require_origin_verify ? 1 : 0) <= 5
    ])
    error_message = "A rule can have at most 5 condition values in total (path patterns, host headers and the origin verify header)."
  }
}

variable "origin_verify_header_name" {
  type        = string
  default     = null
  description = "Header the CDN adds to origin requests. Give it together with origin_verify_header_value."
  validation {
    condition     = (var.origin_verify_header_name == null) == nonsensitive(var.origin_verify_header_value == null)
    error_message = "origin_verify_header_name and origin_verify_header_value must be given together or not at all."
  }
}

variable "origin_verify_header_value" {
  type        = string
  default     = null
  sensitive   = true
  description = "Secret value of the origin verify header. Pass it from a TF_VAR_ environment variable, never from a tfvars file."
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
