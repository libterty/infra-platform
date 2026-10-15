variable "certificate_arn" {
  description = "ACM certificate for the HTTPS listener. null opens HTTP only, which the network stack must have narrowed (alb_ingress.https = false). It must agree with network/alb_https."
  type        = string
  default     = null
}

variable "access_logs_enabled" {
  description = "Write ALB access logs to the foundation bucket. The bucket exists in every environment; this only decides whether it is used."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle timeout in seconds. Raise it (for example to 300) for long-lived connections such as SSE."
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Block deletion of the ALB."
  type        = bool
  default     = true
}

variable "web_acl_arn" {
  description = "Regional WAFv2 Web ACL to associate. The Web ACL itself is not created by this template."
  type        = string
  default     = null
}
