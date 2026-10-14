variable "name" {
  type        = string
  description = "Alarm name prefix, usually the service name; alarms are named <name>-<key>."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,200}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens."
  }
}

variable "cluster_name" {
  type        = string
  description = "ECS cluster name (CloudWatch ClusterName dimension)."
}

variable "service_name" {
  type        = string
  description = "ECS service name (CloudWatch ServiceName dimension)."
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions. Required: an alarm nobody receives is not an alarm."
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "load_balancer" {
  type = object({
    alb_arn_suffix          = string # app/<name>/<id>
    target_group_arn_suffix = string # targetgroup/<name>/<id>
  })
  default     = null
  description = "null creates no ALB target alarms."
  validation {
    condition     = var.load_balancer == null ? true : (startswith(var.load_balancer.alb_arn_suffix, "app/") && startswith(var.load_balancer.target_group_arn_suffix, "targetgroup/"))
    error_message = "Use ARN suffixes: app/... and targetgroup/... (CloudWatch dimension format)."
  }
}

variable "max_capacity" {
  type        = number
  default     = null
  description = "Autoscaling max capacity; a number adds the at_max_capacity alarm."
}

variable "alarm_config" {
  type = object({
    ecs = optional(object({
      cpu_threshold    = optional(number, 80)
      memory_threshold = optional(number, 80)
    }), {})
    container = optional(object({
      cpu_throttling_threshold  = optional(number, 0.9)
      memory_pressure_threshold = optional(number, 0.85)
    }), {})
    alb = optional(object({
      target_5xx_ratio_threshold = optional(number, 0.01)
      target_4xx_ratio_threshold = optional(number, 0.05)
      latency_p95_threshold_ms   = optional(number, 800)
      healthy_host_min           = optional(number, 1)
    }), {})
  })
  default = {}
}

variable "dashboard_name" {
  type        = string
  default     = null
  description = "null creates no dashboard."
}

variable "tags" {
  type    = map(string)
  default = {}
}
