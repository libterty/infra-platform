variable "name" {
  type        = string
  description = "Replication group id. Also names the subnet group, the parameter group and the log groups. 40 chars at most."
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 1-40 chars: lowercase letters, digits and hyphens, starting with a letter, not ending with a hyphen, no consecutive hyphens."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Replication group description. Defaults to a generated text."
}

variable "engine_version" {
  type        = string
  description = "Redis engine version, major 6 or 7 (for example 7.1 or 6.x). The parameter group family is derived from the major version."
  validation {
    condition     = can(regex("^[67]\\.([0-9]+|x)$", var.engine_version))
    error_message = "engine_version must look like 7.1, 7.0, 6.2 or 6.x (Redis 6 or 7)."
  }
}

variable "node_type" {
  type        = string
  description = "Node type, for example cache.r7g.large. cache.t* cannot be combined with autoscaling."
  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.node_type))
    error_message = "node_type must look like cache.r7g.large."
  }
}

variable "port" {
  type        = number
  default     = 6379
  description = "Port the cluster listens on."
  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the subnet group. At least 2, in different AZs, because multi-AZ is always on."
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids needs at least 2 subnets (multi-AZ is always on)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups attached to the cluster. Access control relies on these and TLS, there is no AUTH token."
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "security_group_ids needs at least 1 security group."
  }
}

variable "num_node_groups" {
  type        = number
  default     = 1
  description = "Initial number of shards. Ignored after creation (autoscaling owns the shard count), so changing it later has no effect."
  validation {
    condition     = var.num_node_groups >= 1 && var.num_node_groups <= 500
    error_message = "num_node_groups must be between 1 and 500."
  }
}

variable "replicas_per_node_group" {
  type        = number
  default     = 1
  description = "Replicas per shard. At least 1 because automatic failover and multi-AZ are always on."
  validation {
    condition     = var.replicas_per_node_group >= 1 && var.replicas_per_node_group <= 5
    error_message = "replicas_per_node_group must be between 1 and 5 (at least 1 replica: failover and multi-AZ are always on)."
  }
}

variable "parameters" {
  type        = map(string)
  default     = {}
  description = "Extra parameter group parameters. cluster-enabled is fixed to yes and cannot be set here."
  validation {
    condition     = !contains([for k in keys(var.parameters) : lower(k)], "cluster-enabled")
    error_message = "parameters must not set cluster-enabled: this module is always cluster mode enabled."
  }
}

variable "snapshot_retention_limit" {
  type        = number
  default     = 0
  description = "Days to keep automatic snapshots. 0 turns snapshots off."
  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 0 and 35."
  }
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply modifications immediately instead of in the next maintenance window."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key for at-rest encryption and the two log groups. Its key policy must allow logs.<region>.amazonaws.com. Null uses the AWS managed keys."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention in days of the slow log and engine log groups. Never-expire (0) is not accepted."
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "autoscaling" {
  type = object({
    min_shards = number
    max_shards = number
    target_cpu = optional(number, 70)
  })
  default     = null
  description = "Optional shard autoscaling on primary engine CPU. Not available for cache.t* node types."
  validation {
    condition = var.autoscaling == null ? true : (
      var.autoscaling.min_shards >= 1 &&
      var.autoscaling.max_shards <= 500 &&
      var.autoscaling.min_shards <= var.autoscaling.max_shards &&
      var.num_node_groups >= var.autoscaling.min_shards &&
      var.num_node_groups <= var.autoscaling.max_shards &&
      var.autoscaling.target_cpu > 0 &&
      var.autoscaling.target_cpu <= 100 &&
      !startswith(var.node_type, "cache.t")
    )
    error_message = "autoscaling needs 1 <= min_shards <= max_shards <= 500 with num_node_groups inside that range, 0 < target_cpu <= 100, and a node_type that is not cache.t*."
  }
}

variable "alarm_config" {
  type = object({
    memory_percent      = optional(number, 80)
    evictions_threshold = optional(number)
  })
  default     = {}
  description = "Alarm thresholds. memory_percent applies to DatabaseMemoryUsagePercentage of every member. The evictions alarm is created only when evictions_threshold is set."
  validation {
    condition = (
      var.alarm_config.memory_percent > 0 && var.alarm_config.memory_percent <= 100 &&
      (var.alarm_config.evictions_threshold == null ? true : var.alarm_config.evictions_threshold > 0)
    )
    error_message = "alarm_config.memory_percent must be in (0, 100] and evictions_threshold, when set, must be greater than 0."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "SNS topics notified on alarm and on OK. Required."
  validation {
    condition     = length(var.sns_topic_arns) >= 1 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:", a))])
    error_message = "sns_topic_arns needs at least 1 SNS topic ARN."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource. Name is added by the module."
}
