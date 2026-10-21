variable "name" {
  type        = string
  description = "NLB name, 2-32 characters. Target groups are named <name>-<key>."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,30}[a-zA-Z0-9]$", var.name)) && !startswith(var.name, "internal-")
    error_message = "name must be 2-32 letters, digits or hyphens, not starting or ending with a hyphen nor starting with internal-."
  }
}

variable "internal" {
  type        = bool
  default     = true
  description = "true creates an internal NLB."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets of the NLB, in at least two AZs."
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups created by the network stack. A security group can only be attached when the NLB is created (not confirmed)."
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "Give at least one security group (created by the network stack)."
  }
}

variable "cross_zone" {
  type        = bool
  default     = true
  description = "enable_cross_zone_load_balancing."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "enable_deletion_protection."
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
    protocol             = optional(string, "TCP") # TCP, TLS, UDP or TCP_UDP
    target_type          = optional(string, "ip")  # ip, instance or alb
    deregistration_delay = optional(number, 300)   # seconds, 0-3600
    preserve_client_ip   = optional(bool)          # null keeps the AWS default
    health_check = optional(object({
      protocol            = optional(string, "TCP") # TCP, HTTP or HTTPS
      port                = optional(string, "traffic-port")
      path                = optional(string, "/") # HTTP and HTTPS only
      matcher             = optional(string, "200-399")
      interval            = optional(number, 30) # seconds, 5-300
      healthy_threshold   = optional(number, 3)  # 2-10
      unhealthy_threshold = optional(number, 3)  # 2-10
    }), {})
    stickiness   = optional(bool, false) # source_ip
    dns_failover = optional(string, "1") # "off" or 1-3000 (minimum healthy targets per zone)
  }))
  default     = {}
  description = "Key => target group named <name>-<key>. dns_failover is target_group_health.dns_failover.minimum_healthy_targets_count: a listener with more than one target needs it to be \"off\" on every target group it uses from this module."
  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,30}[a-zA-Z0-9])?$", "${var.name}-${k}"))])
    error_message = "<name>-<key> must be 1-32 letters, digits or hyphens, not starting or ending with a hyphen."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.port >= 1 && t.port <= 65535])
    error_message = "port must be 1-65535."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["TCP", "TLS", "UDP", "TCP_UDP"], t.protocol)])
    error_message = "protocol must be TCP, TLS, UDP or TCP_UDP."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["ip", "instance", "alb"], t.target_type)])
    error_message = "target_type must be ip, instance or alb."
  }
  # An alb target group needs TCP and an HTTP or HTTPS health check (AWS documentation; not verified against a real apply).
  validation {
    condition = alltrue([
      for t in values(var.target_groups) : t.target_type != "alb" || (t.protocol == "TCP" && contains(["HTTP", "HTTPS"], t.health_check.protocol))
    ])
    error_message = "A target group with target_type alb needs protocol TCP and health_check.protocol HTTP or HTTPS."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.deregistration_delay >= 0 && t.deregistration_delay <= 3600])
    error_message = "deregistration_delay must be 0-3600 seconds."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["TCP", "HTTP", "HTTPS"], t.health_check.protocol)])
    error_message = "health_check.protocol must be TCP, HTTP or HTTPS."
  }
  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.health_check.interval >= 5 && t.health_check.interval <= 300])
    error_message = "health_check.interval must be 5-300 seconds."
  }
  validation {
    condition = alltrue([
      for t in values(var.target_groups) :
      t.health_check.healthy_threshold >= 2 && t.health_check.healthy_threshold <= 10 && t.health_check.unhealthy_threshold >= 2 && t.health_check.unhealthy_threshold <= 10
    ])
    error_message = "health_check.healthy_threshold and unhealthy_threshold must be 2-10."
  }
  validation {
    condition = alltrue([
      for t in values(var.target_groups) :
      t.dns_failover == "off" || (can(regex("^[1-9][0-9]{0,3}$", t.dns_failover)) && try(tonumber(t.dns_failover) <= 3000, false))
    ])
    error_message = "dns_failover must be \"off\" or a number from 1 to 3000 written as a string."
  }
}

variable "listeners" {
  type = map(object({
    port            = number
    protocol        = optional(string, "TCP") # TCP, TLS, UDP or TCP_UDP
    certificate_arn = optional(string)        # required for TLS, not allowed otherwise
    ssl_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    alpn_policy     = optional(string) # TLS only
    targets = map(object({
      target_group     = optional(string) # key of target_groups
      target_group_arn = optional(string) # external target group; exactly one of the two
      weight           = optional(number, 1)
    }))
  }))
  default     = {}
  description = "Key => listener whose default action forwards to 1-5 weighted targets (weight 0-999, at least one above 0). A listener with more than one target needs dns_failover = \"off\" on every target group it uses from this module; external ARNs cannot be checked."
  validation {
    condition     = alltrue([for l in values(var.listeners) : l.port >= 1 && l.port <= 65535])
    error_message = "Listener port must be 1-65535."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : contains(["TCP", "TLS", "UDP", "TCP_UDP"], l.protocol)])
    error_message = "Listener protocol must be TCP, TLS, UDP or TCP_UDP."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol != "TLS" || l.certificate_arn != null])
    error_message = "A TLS listener needs certificate_arn."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol == "TLS" || l.certificate_arn == null])
    error_message = "certificate_arn is only allowed on a TLS listener."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.certificate_arn == null ? true : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/", l.certificate_arn))
    ])
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) :
      l.alpn_policy == null ? true : l.protocol == "TLS" && contains(["HTTP1Only", "HTTP2Only", "HTTP2Optional", "HTTP2Preferred", "None"], l.alpn_policy)
    ])
    error_message = "alpn_policy is only allowed on a TLS listener and must be HTTP1Only, HTTP2Only, HTTP2Optional, HTTP2Preferred or None."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : length(l.targets) >= 1 && length(l.targets) <= 5])
    error_message = "A listener needs 1-5 targets."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : alltrue([for t in values(l.targets) : t.weight >= 0 && t.weight <= 999])])
    error_message = "Target weight must be 0-999."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : anytrue([for t in values(l.targets) : t.weight > 0])])
    error_message = "At least one target of a listener must have a weight above 0."
  }
  validation {
    condition     = alltrue([for l in values(var.listeners) : alltrue([for t in values(l.targets) : (t.target_group != null) != (t.target_group_arn != null)])])
    error_message = "Every target needs exactly one of target_group and target_group_arn."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) : alltrue([
        for t in values(l.targets) : t.target_group == null ? true : contains(keys(var.target_groups), t.target_group)
      ])
    ])
    error_message = "Every target target_group must be a key of target_groups."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) : alltrue([
        for t in values(l.targets) :
        t.target_group_arn == null ? true : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]+/[a-f0-9]+$", t.target_group_arn))
      ])
    ])
    error_message = "target_group_arn must be an ELB target group ARN (arn:aws:elasticloadbalancing:<region>:<account>:targetgroup/<name>/<id>)."
  }
  # D14: more than one target means every module target group must have DNS failover off, or one zone without healthy new targets drops the whole zone from DNS.
  validation {
    condition = alltrue([
      for l in values(var.listeners) : length(l.targets) <= 1 || alltrue([
        for t in values(l.targets) : t.target_group == null ? true : try(var.target_groups[t.target_group].dns_failover == "off", false)
      ])
    ])
    error_message = "A listener with more than one target needs dns_failover = \"off\" on every target group it uses from target_groups (external ARNs cannot be checked)."
  }
  # Targets of one listener must share a protocol; only the module's own target groups can be checked.
  validation {
    condition = alltrue([
      for l in values(var.listeners) : length(distinct([
        for t in values(l.targets) : var.target_groups[t.target_group].protocol if t.target_group != null && contains(keys(var.target_groups), t.target_group)
      ])) <= 1
    ])
    error_message = "All target groups of one listener must have the same protocol."
  }
  validation {
    condition = alltrue([
      for l in values(var.listeners) : l.protocol != "TLS" || !anytrue([
        for t in values(l.targets) : try(var.target_groups[t.target_group].stickiness, false)
      ])
    ])
    error_message = "A TLS listener cannot use a target group with stickiness."
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

variable "tags" {
  type    = map(string)
  default = {}
}
