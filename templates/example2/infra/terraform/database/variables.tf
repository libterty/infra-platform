variable "db_name" {
  description = "Name of the initial database. pg_cron also runs its jobs in it."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must be lowercase letters, digits or underscores, starting with a letter."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL major.minor, for example 16.6."
  type        = string
}

variable "db_instance_class" {
  description = "Instance class of the writer and of every reader."
  type        = string
}

variable "db_reader_count" {
  description = "Aurora readers. 0 also removes the Proxy read-only endpoint."
  type        = number
  default     = 1

  validation {
    condition     = var.db_reader_count >= 0 && var.db_reader_count <= 15
    error_message = "db_reader_count must be 0-15."
  }
}

variable "connections_threshold" {
  description = "Connection count that raises the connections alarm. max_connections depends on the instance class, so set it to about 80 percent of the value of the class in db_instance_class; the module cannot derive it for provisioned Aurora."
  type        = number

  validation {
    condition     = var.connections_threshold > 0
    error_message = "connections_threshold must be positive."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block deletion of the cluster. Leave true anywhere that holds data worth keeping."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when the cluster is destroyed."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention of the PostgreSQL, Proxy and Redis log groups."
  type        = number
  default     = 14
}

variable "redis" {
  description = "The two Redis clusters, keyed rate-limit and stream. Both keys are required; parameters are fixed in redis.tf."
  type = map(object({
    node_type         = string
    num_node_groups   = optional(number, 1)
    engine_version    = optional(string, "7.1")
    apply_immediately = optional(bool, false)
    # Burstable (cache.t*) node types cannot be combined with autoscaling.
    autoscaling = optional(object({
      min_shards = number
      max_shards = number
      target_cpu = optional(number, 70)
    }))
  }))

  validation {
    condition     = toset(keys(var.redis)) == toset(["rate-limit", "stream"])
    error_message = "redis must have exactly the keys rate-limit and stream."
  }
}
