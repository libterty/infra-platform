variable "app_port" {
  description = "Port the api container listens on. It must equal app_port in the network stack and in the loadbalancer stack."
  type        = number
  default     = 8080
}

variable "stream_length_cap" {
  description = "Per-shard stream length cap; the worker's backlog thresholds are fractions of it."
  type        = number
  default     = 100000

  validation {
    condition     = var.stream_length_cap >= 20
    error_message = "stream_length_cap is the per-shard length cap and must be 20 or more."
  }
}

variable "cors_allow_origins" {
  description = "Origins the api allows for browser calls."
  type        = list(string)
}

variable "trusted_proxies" {
  description = "Which proxies the api trusts to set X-Forwarded-For. any trusts every hop, so a client can spoof its address; vpc trusts the VPC only; vpc_and_cdn also trusts the CloudFront origin-facing ranges."
  type        = string
  default     = "vpc"

  validation {
    condition     = contains(["any", "vpc", "vpc_and_cdn"], var.trusted_proxies)
    error_message = "trusted_proxies accepts only the values any, vpc and vpc_and_cdn."
  }
}

variable "api_min_capacity" {
  description = "Lowest api replica count."
  type        = number
  default     = 2
}

variable "api_max_capacity" {
  description = "Highest api replica count. Every replica opens connections to the database proxy and Redis, so raise it only after checking those limits."
  type        = number
  default     = 10
}

variable "api_requests_per_target" {
  description = "Target ALB requests per api replica (KEDA trigger on RequestCountPerTarget)."
  type        = number
  default     = 300
}

variable "api_cpu_target_percent" {
  description = "Target average api CPU utilization."
  type        = number
  default     = 60
}

variable "api_streams_per_task_high" {
  description = "Target ALB active connections per api replica (KEDA trigger on ActiveConnectionCount)."
  type        = number
  default     = 100
}

variable "worker_min_capacity" {
  description = "Lowest worker replica count."
  type        = number
  default     = 2
}

variable "worker_max_capacity" {
  description = "Highest worker replica count."
  type        = number
  default     = 6
}
