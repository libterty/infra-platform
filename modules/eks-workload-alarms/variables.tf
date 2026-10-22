variable "name" {
  type        = string
  description = "Alarm name prefix, usually the workload name; alarms are named <name>-<key>."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,200}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens."
  }
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name (Container Insights ClusterName dimension)."
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace of the workload (Namespace dimension)."
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a Kubernetes DNS label: lowercase letters, digits or hyphens, up to 63 characters."
  }
}

variable "workload_name" {
  type        = string
  description = "Deployment name; Container Insights reports it in the PodName dimension."
  validation {
    condition     = length(var.workload_name) > 0
    error_message = "workload_name must not be empty."
  }
}

variable "container_name" {
  type        = string
  description = "Container name inside the pod (ContainerName dimension of the OOM alarm)."
  validation {
    condition     = length(var.container_name) > 0
    error_message = "container_name must not be empty."
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

variable "restart_threshold" {
  type        = number
  default     = 0
  description = "The restarts alarm fires when the container restarts in a 5-minute period exceed this number."
  validation {
    condition     = var.restart_threshold >= 0
    error_message = "restart_threshold must be 0 or more."
  }
}

variable "alarm_config" {
  type = object({
    alb = optional(object({
      target_5xx_ratio_threshold = optional(number, 0.01)
      latency_p95_threshold_ms   = optional(number, 800)
      healthy_host_min           = optional(number, 1)
    }), {})
  })
  default     = {}
  description = "Threshold overrides for the ALB alarms; every field has a default."
  validation {
    condition     = var.alarm_config.alb.target_5xx_ratio_threshold >= 0 && var.alarm_config.alb.latency_p95_threshold_ms > 0 && var.alarm_config.alb.healthy_host_min >= 0
    error_message = "ALB thresholds: ratio and healthy_host_min must be 0 or more, latency_p95_threshold_ms must be above 0."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every alarm."
}
