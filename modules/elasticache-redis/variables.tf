variable "name" {
  type        = string
  description = "replication group ID，也用來命名 subnet group、參數群組與 log group。1–40 字元，限小寫英數與連字號，字母開頭，不可連續連字號或以連字號結尾。"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 1-40 chars: lowercase letters, digits and hyphens, starting with a letter, not ending with a hyphen, no consecutive hyphens."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "replication group 的說明；`null` 時自動產生。"
}

variable "engine_version" {
  type        = string
  description = "Redis 引擎版本，主版本 6 或 7，例如 `7.1`、`7.0`、`6.2`、`6.x`。參數群組 family 由主版本推得。"
  validation {
    condition     = can(regex("^[67]\\.([0-9]+|x)$", var.engine_version))
    error_message = "engine_version must look like 7.1, 7.0, 6.2 or 6.x (Redis 6 or 7)."
  }
}

variable "node_type" {
  type        = string
  description = "節點類型，例如 `cache.r7g.large`。`cache.t*` 不能搭配 `autoscaling`。"
  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.node_type))
    error_message = "node_type must look like cache.r7g.large."
  }
}

variable "port" {
  type        = number
  default     = 6379
  description = "cluster 監聽的 port，1–65535。"
  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "subnet group 用的 subnet，至少 2 個、分屬不同 AZ（multi-AZ 一律開啟）。"
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids needs at least 2 subnets (multi-AZ is always on)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "掛在 cluster 上的 security group，至少 1 個。存取控制靠這些 security group 與 TLS，沒有 AUTH token。"
  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "security_group_ids needs at least 1 security group."
  }
}

variable "num_node_groups" {
  type        = number
  default     = 1
  description = "初始 shard 數，1–500。建好後會被忽略（shard 數交給 autoscaling），之後改它不會生效。"
  validation {
    condition     = var.num_node_groups >= 1 && var.num_node_groups <= 500
    error_message = "num_node_groups must be between 1 and 500."
  }
}

variable "replicas_per_node_group" {
  type        = number
  default     = 1
  description = "每個 shard 的 replica 數，1–5。至少 1 個，因為 automatic failover 與 multi-AZ 一律開啟。"
  validation {
    condition     = var.replicas_per_node_group >= 1 && var.replicas_per_node_group <= 5
    error_message = "replicas_per_node_group must be between 1 and 5 (at least 1 replica: failover and multi-AZ are always on)."
  }
}

variable "parameters" {
  type        = map(string)
  default     = {}
  description = "參數群組的額外參數。`cluster-enabled` 固定為 `yes`，不能在這裡設定。"
  validation {
    condition     = !contains([for k in keys(var.parameters) : lower(k)], "cluster-enabled")
    error_message = "parameters must not set cluster-enabled: this module is always cluster mode enabled."
  }
}

variable "snapshot_retention_limit" {
  type        = number
  default     = 0
  description = "自動 snapshot 保留天數，0–35；`0` 時不做 snapshot。"
  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 0 and 35."
  }
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "是否立即套用修改；`false` 時等下一個維護時段。"
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "at-rest 加密與兩個 log group 用的 customer managed key，key policy 必須允許 `logs.<region>.amazonaws.com`。`null` 時用 AWS managed key。"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "slow log 與 engine log 兩個 log group 的保留天數，限 CloudWatch Logs 接受的值（1、3、5、7、14、30、60、90 … 3653），不接受 `0`（永久保留）。"
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
  description = "依 primary 引擎 CPU 自動調整 shard 數；`null` 時不開，`cache.t*` 不能用。欄位：`min_shards`、`max_shards`（必填，`1 <= min_shards <= max_shards <= 500`，且 `num_node_groups` 要落在這個範圍內）、`target_cpu`（預設 `70`，大於 0、最多 100）。"
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
  description = "告警門檻。欄位：`memory_percent`（預設 `80`，大於 0、最多 100，套用到每個 member 的 `DatabaseMemoryUsagePercentage`）、`evictions_threshold`（預設 `null`，有給才建 evictions 告警，必須大於 0）。"
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
  description = "告警與恢復 OK 時通知的 SNS topic ARN，至少 1 個。"
  validation {
    condition     = length(var.sns_topic_arns) >= 1 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:", a))])
    error_message = "sns_topic_arns needs at least 1 SNS topic ARN."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個資源的 tag；`Name` 由 module 加上。"
}
