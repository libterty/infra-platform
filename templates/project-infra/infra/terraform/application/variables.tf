variable "services" {
  description = "Per-service settings. The keys must equal the services published by containerimage. Everything that belongs to another stack (roles, subnets, security groups, the image repository, the ALB listener, database endpoints) is read from SSM, never set here."
  type = map(object({
    image_tag        = string # unique per build, for example the git SHA; ECR repositories are immutable and latest is rejected
    container_port   = optional(number)
    cpu              = optional(number, 512)
    memory           = optional(number, 1024)
    cpu_architecture = optional(string, "ARM64") # must match the image
    desired_count    = optional(number, 2)
    max_capacity     = optional(number) # null keeps a fixed task count of desired_count
    alb = optional(object({             # null: the service is not behind the ALB
      priority            = number
      path_patterns       = optional(list(string), [])
      host_headers        = optional(list(string), [])
      requests_per_target = optional(number) # null scales on CPU only
    }))
  }))

  validation {
    condition     = alltrue([for s in values(var.services) : length(s.image_tag) > 0])
    error_message = "Every service needs an image_tag."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.alb == null || s.container_port != null])
    error_message = "A service behind the ALB needs a container_port."
  }
}

variable "log_alarms" {
  description = "Alarms on log patterns. Service name => alarm key => settings; the service must exist in containerimage. Empty creates nothing. Settings that are left out use the log-metric-alarm defaults."
  type = map(map(object({
    pattern             = string
    metric_name         = string
    description         = string # what it means and what to check first
    metric_value        = optional(string)
    default_value       = optional(number)
    statistic           = optional(string)
    period              = optional(number)
    evaluation_periods  = optional(number)
    datapoints_to_alarm = optional(number)
    threshold           = optional(number)
    comparison_operator = optional(string)
    treat_missing_data  = optional(string)
  })))
  default = {}
}

variable "xray_sampling_rules" {
  description = "X-Ray sampling rules by short name. Empty creates nothing. They only apply to SDKs or collectors that use remote sampling."
  type = map(object({
    priority       = number
    fixed_rate     = number
    reservoir_size = optional(number)
    service_name   = optional(string)
    service_type   = optional(string)
    host           = optional(string)
    http_method    = optional(string)
    url_path       = optional(string)
    attributes     = optional(map(string))
  }))
  default = {}
}

variable "xray_groups" {
  description = "X-Ray groups by short name. Empty creates nothing."
  type = map(object({
    filter_expression     = string
    insights_enabled      = optional(bool)
    notifications_enabled = optional(bool)
  }))
  default = {}
}

variable "adot_collector" {
  description = "ADOT collector image, used only for the services that iam-app traces; there is no tracing switch in this stack. tag must be explicit (never latest). source public pulls from ECR Public and needs a NAT; mirror pulls from the mirror repository adot-collector of containerimage (mirrored_images) and is required when network has no NAT. Required once iam-app traces any service."
  type = object({
    tag    = string
    source = string
  })
  default = null

  validation {
    condition     = var.adot_collector == null ? true : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.adot_collector.tag)) && lower(var.adot_collector.tag) != "latest"
    error_message = "adot_collector.tag must be an explicit image tag, not latest."
  }

  validation {
    condition     = var.adot_collector == null ? true : contains(["public", "mirror"], var.adot_collector.source)
    error_message = "adot_collector.source must be public or mirror."
  }
}
