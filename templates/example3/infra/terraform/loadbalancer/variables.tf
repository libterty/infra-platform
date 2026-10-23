variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener. null serves HTTP only, which suits an ALB behind a CDN that connects over HTTP."
  type        = string
  default     = null
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds. It must exceed the longest streaming response."
  type        = number
  default     = 300
}

variable "deletion_protection" {
  description = "Block deletion of the ALB."
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Port the api containers listen on. It must equal app_port in the network stack, which opens the security group to it."
  type        = number
  default     = 8080
}

variable "deregistration_delay" {
  description = "Seconds a draining target keeps its connections; long enough for in-flight streams to finish."
  type        = number
  default     = 300
}

variable "dev_page_enabled" {
  description = "Route the manual test page to the api, without the origin verify condition."
  type        = bool
  default     = false
}

variable "origin_verify_header_name" {
  description = "Header the CDN adds to origin requests. Only the name lives here; the value comes from TF_VAR_origin_verify_header_value."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,64}$", var.origin_verify_header_name))
    error_message = "origin_verify_header_name must be 1-64 letters, digits or hyphens."
  }
}

variable "origin_verify_header_value" {
  description = "Secret value of the origin verify header. Export TF_VAR_origin_verify_header_value; never write it in a tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = nonsensitive(length(var.origin_verify_header_value) >= 16)
    error_message = "origin_verify_header_value must be at least 16 characters."
  }
}

variable "origin_verify_host_headers" {
  description = "Host headers the origin verify rules also require. Empty adds no host condition."
  type        = list(string)
  default     = []
}

variable "rate_limit_per_5min" {
  description = "Requests per source IP in five minutes above which the WAF blocks."
  type        = number
  default     = 2000
}

variable "rate_limit_allowlist_cidrs" {
  description = "IPv4 CIDRs exempt from the rate limit only; they stay subject to every other WAF rule."
  type        = list(string)
  default     = []
}

variable "waf_kill_switch_mode" {
  description = "WAF kill switch: count while healthy, block to stop all ingress with a 503."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_kill_switch_mode)
    error_message = "waf_kill_switch_mode accepts only count (observe) or block (reject all traffic)."
  }
}

variable "body_size_exempt_path_prefixes" {
  description = "Path prefixes exempt from the 8 KB body size limit. Bodies there have no limit at the WAF, so the application must set its own."
  type        = list(string)
  default     = ["/api/admin"]
}

variable "waf_log_retention_days" {
  description = "Retention of the WAF log group."
  type        = number
  default     = 14
}

variable "access_log_retention_days" {
  description = "Days ALB access logs are kept in the bucket."
  type        = number
  default     = 14
}

variable "canary" {
  description = <<-EOT
    Weighted canary of the api (design v4 §6.1); null creates nothing. weight (0-100) goes to the api-canary target
    group, the rest to api, on the three api rules. CI deploys a second release bound to api_canary_target_group_arn
    (deploy/values-from-ssm.sh --canary). breaker adds lb-traffic-breaker: alarms on the canary target group and a
    Lambda (image <project>-traffic-breaker:<image_tag>) that moves all traffic back to api. A weight above 0 needs
    the breaker. After a trip, set weight to 0 here and apply before anything else (the next apply restores weight).
  EOT
  type = object({
    weight = number
    breaker = optional(object({
      image_tag          = string
      error_rate_percent = optional(number, 5)
      min_requests       = optional(number, 50)
      min_healthy_hosts  = optional(number, 1)
    }))
  })
  default = null

  validation {
    condition     = var.canary == null ? true : var.canary.weight >= 0 && var.canary.weight <= 100 && var.canary.weight == floor(var.canary.weight)
    error_message = "canary.weight must be a whole number from 0 to 100."
  }

  validation {
    condition     = var.canary == null ? true : var.canary.weight == 0 || var.canary.breaker != null
    error_message = "A canary weight above 0 needs canary.breaker: nothing else moves the traffic back when the canary fails."
  }

  # Target group names are <alb name>-<key> and AWS caps them at 32 characters; api-canary is the longest key.
  validation {
    condition     = var.canary == null ? true : length("${var.project}-${var.env}-alb-api-canary") <= 32
    error_message = "The canary target group would be named ${var.project}-${var.env}-alb-api-canary, longer than the 32 characters AWS allows; shorten project or env."
  }

  validation {
    condition     = try(var.canary.breaker.image_tag, null) == null ? true : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.canary.breaker.image_tag)) && var.canary.breaker.image_tag != "latest"
    error_message = "canary.breaker.image_tag must be an image tag other than latest."
  }
}
