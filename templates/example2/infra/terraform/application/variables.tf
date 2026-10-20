variable "api_image_tag" {
  description = "Image tag of the api service. Terraform owns it: change it here and apply."
  type        = string
}

variable "worker_image_tag" {
  description = "Image tag of the worker service. Terraform owns it: change it here and apply."
  type        = string
}

variable "app_port" {
  description = "Port the api container listens on. It must equal app_port in the network stack and in the loadbalancer stack."
  type        = number
  default     = 8080
}

variable "db_name" {
  description = "Database name. It must equal db_name in the database stack, which does not publish it."
  type        = string
  default     = "app"
}

variable "stream_shard_count" {
  description = "Shards of the stream Redis. It must equal that cluster's num_node_groups in the database stack."
  type        = number
  default     = 1
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

variable "enable_execute_command" {
  description = "Allow ECS Exec into the tasks. Both task roles carry the ssmmessages permissions it needs."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the service log groups."
  type        = number
  default     = 14
}

variable "api_cpu" {
  description = "api task CPU units."
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "api task memory in MiB; must pair with api_cpu."
  type        = number
  default     = 1024
}

variable "api_min_capacity" {
  description = "Lowest api task count."
  type        = number
  default     = 2
}

variable "api_max_capacity" {
  description = "Highest api task count. Every task opens connections to the database proxy and Redis, so raise it only after checking those limits."
  type        = number
  default     = 10
}

variable "api_requests_per_target" {
  description = "Target ALB requests per api task."
  type        = number
  default     = 300
}

variable "api_cpu_target_percent" {
  description = "Target average api CPU utilization."
  type        = number
  default     = 60
}

variable "api_streams_per_task_high" {
  description = "Approximate active streams per api task above which the step policy adds tasks."
  type        = number
  default     = 100
}

variable "api_scheduled_scaling" {
  description = "Capacity windows of the api, keyed by name. max_capacity must not exceed api_max_capacity."
  type = map(object({
    schedule     = string
    timezone     = optional(string, "UTC")
    min_capacity = number
    max_capacity = number
  }))
  default = {}

  validation {
    condition     = alltrue([for w in values(var.api_scheduled_scaling) : w.max_capacity <= var.api_max_capacity])
    error_message = "Every scheduled window must keep max_capacity at or below api_max_capacity."
  }
}

variable "worker_cpu" {
  description = "worker task CPU units."
  type        = number
  default     = 256
}

variable "worker_memory" {
  description = "worker task memory in MiB; must pair with worker_cpu."
  type        = number
  default     = 512
}

variable "worker_min_capacity" {
  description = "Lowest worker task count."
  type        = number
  default     = 2
}

variable "worker_max_capacity" {
  description = "Highest worker task count."
  type        = number
  default     = 6
}
