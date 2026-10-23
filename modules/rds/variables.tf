variable "name" {
  description = "完整名稱，用作 DB 識別碼，也是所有相關資源名稱的基底。小寫字母開頭，限小寫英數與單一連字號，不可以連字號結尾，最長 50 字元。"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,49}$", var.name)) && !strcontains(var.name, "--") && !endswith(var.name, "-")
    error_message = "name must start with a letter, use lowercase letters, digits and single hyphens, and be at most 50 chars."
  }
}

variable "deployment" {
  description = "資料庫型態：`rds`（單一 instance）、`aurora`（provisioned cluster）或 `aurora_serverless`（Serverless v2 cluster）。對應的物件（`rds`、`aurora`、`serverless`）必填，另外兩個必須是 `null`。"
  type        = string

  validation {
    condition     = contains(["rds", "aurora", "aurora_serverless"], var.deployment)
    error_message = "deployment must be rds, aurora or aurora_serverless."
  }

  validation {
    condition = (
      var.deployment == "rds" ? (var.rds != null && var.aurora == null && var.serverless == null) :
      var.deployment == "aurora" ? (var.aurora != null && var.rds == null && var.serverless == null) :
      var.deployment == "aurora_serverless" ? (var.serverless != null && var.rds == null && var.aurora == null) :
      true
    )
    error_message = "Give only the object matching deployment (rds, aurora or serverless); the other two must be null."
  }
}

variable "engine_version" {
  description = "PostgreSQL 版本，格式 `major.minor`（例如 `16.4`），major 限 13–17，決定參數群組 family。"
  type        = string

  validation {
    condition     = can(regex("^1[3-7]\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be major.minor for PostgreSQL 13-17."
  }
}

variable "database_name" {
  description = "初始資料庫名稱，小寫字母開頭，限小寫英數與 `_`，最長 63 字元。"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be lowercase letters, digits or underscores, starting with a letter."
  }
}

variable "master_username" {
  description = "master 帳號名稱。密碼由 RDS 產生並放在 Secrets Manager，module 沒有密碼變數。"
  type        = string
  default     = "dbadmin"
}

variable "subnet_ids" {
  description = "data tier 的 subnet，至少兩個、分屬不同 AZ。"
  type        = list(string)

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "Give at least two subnets in different AZs."
  }
}

variable "security_group_ids" {
  description = "DB 的 security group，由 network stack 建立。"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "儲存與 Performance Insights 用的 KMS key；`null` 時用 AWS managed key（`aws/rds`）。"
  type        = string
  default     = null
}

variable "master_user_secret_kms_key_arn" {
  description = "master 帳號 secret 的 KMS key；`null` 時用 `aws/secretsmanager`。"
  type        = string
  default     = null
}

variable "backup_retention_days" {
  description = "自動備份保留天數，1–35。"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be 1-35."
  }
}

variable "backup_window" {
  description = "每日備份時段（UTC）。預設 `18:00-19:00` 是台灣時間 02:00–03:00。"
  type        = string
  default     = "18:00-19:00"
}

variable "maintenance_window" {
  description = "每週維護時段（UTC）。預設 `sun:19:00-sun:20:00` 是台灣時間週一 03:00–04:00。"
  type        = string
  default     = "sun:19:00-sun:20:00"
}

variable "deletion_protection" {
  description = "是否擋下 instance 或 cluster 的刪除。"
  type        = bool
  default     = true
}

variable "data_api" {
  description = "在 Aurora cluster 開 RDS Data API（`enable_http_endpoint`），Bedrock Knowledge Base 需要。只限 `aurora`、`aurora_serverless`；`deployment = \"rds\"` 時給 `true` 會被擋下。"
  type        = bool
  default     = false

  validation {
    condition     = var.deployment != "rds" || !var.data_api
    error_message = "data_api needs deployment aurora or aurora_serverless; the Data API does not support RDS DB instances."
  }
}

variable "skip_final_snapshot" {
  description = "destroy 時是否跳過最終 snapshot。"
  type        = bool
  default     = false
}

variable "cluster_parameters" {
  description = "Aurora 的 cluster 參數，蓋過 module 同名的預設值。`deployment = \"rds\"` 時必須為空（改用 `instance_parameters`）。"
  type        = map(string)
  default     = {}

  validation {
    condition     = var.deployment != "rds" || length(var.cluster_parameters) == 0
    error_message = "cluster_parameters must be empty when deployment is rds; use instance_parameters."
  }
}

variable "instance_parameters" {
  description = "instance 參數。`rds` 時併入 module 預設值、放在唯一的參數群組；Aurora 時非空才另建 instance 參數群組。"
  type        = map(string)
  default     = {}
}

variable "static_parameter_names" {
  description = "`cluster_parameters`、`instance_parameters` 裡屬於 static 的參數名稱（例如 `cron.database_name`），改用 `pending-reboot` 套用而不是 `immediate`。跟內建的 `shared_preload_libraries`（一律視為 static）取聯集。0.2.0 起。"
  type        = set(string)
  default     = []
  nullable    = false
}

variable "performance_insights_retention_days" {
  description = "Performance Insights 保留天數：`7`、31 的倍數（最多 713）或 `731`。"
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 731 || (var.performance_insights_retention_days > 0 && var.performance_insights_retention_days <= 713 && var.performance_insights_retention_days % 31 == 0)
    error_message = "performance_insights_retention_days must be 7, 731 or a multiple of 31 up to 713."
  }
}

variable "monitoring" {
  description = "Enhanced Monitoring；`null` 時不開。欄位：`role_arn`（必填，來自 `iam-base` stack）、`interval`（秒，預設 `60`，限 `1`、`5`、`10`、`15`、`30`、`60`）。"
  type = object({
    interval = optional(number, 60)
    role_arn = string
  })
  default = null

  validation {
    condition     = var.monitoring == null ? true : contains([1, 5, 10, 15, 30, 60], var.monitoring.interval)
    error_message = "monitoring.interval must be one of 1, 5, 10, 15, 30, 60."
  }
}

variable "log_retention_days" {
  description = "PostgreSQL 與 Proxy log group 的保留天數。"
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "log group 的 KMS key；`null` 時用 CloudWatch 預設加密。"
  type        = string
  default     = null
}

variable "sns_topic_arns" {
  description = "告警的 `alarm_actions` 與 `ok_actions` 要送的 SNS topic ARN，至少一個。"
  type        = list(string)

  validation {
    condition     = length(var.sns_topic_arns) >= 1 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:.+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "tags" {
  description = "可加 tag 的資源都會帶上的 tag；`Name` 由 module 加上。"
  type        = map(string)
  default     = {}
}

variable "rds" {
  description = "`deployment = \"rds\"` 時的設定，其他型態必須是 `null`。欄位：`instance_class`（必填）、`allocated_storage`（預設 `20`）、`max_allocated_storage`（預設 `null`）、`multi_az`（預設 `false`）、`storage_type`（預設 `gp3`）。"
  type = object({
    instance_class        = string
    allocated_storage     = optional(number, 20)
    max_allocated_storage = optional(number)
    multi_az              = optional(bool, false)
    storage_type          = optional(string, "gp3")
  })
  default = null
}

variable "aurora" {
  description = "`deployment = \"aurora\"` 時的設定，其他型態必須是 `null`。欄位：`instance_class`（必填，以 `db.` 開頭，不可為 `db.serverless`）、`reader_count`（預設 `1`，0–15）。"
  type = object({
    instance_class = string
    reader_count   = optional(number, 1)
  })
  default = null

  validation {
    condition     = var.aurora == null ? true : (startswith(var.aurora.instance_class, "db.") && var.aurora.instance_class != "db.serverless")
    error_message = "aurora.instance_class must start with db. and must not be db.serverless."
  }

  validation {
    condition     = var.aurora == null ? true : (var.aurora.reader_count >= 0 && var.aurora.reader_count <= 15)
    error_message = "aurora.reader_count must be 0-15."
  }
}

variable "serverless" {
  description = "`deployment = \"aurora_serverless\"` 時的設定，其他型態必須是 `null`。欄位：`min_capacity`、`max_capacity`（必填，單位 ACU，0.5 的倍數，`0 <= min_capacity <= max_capacity <= 256`）、`reader_count`（預設 `0`，0–15）。"
  type = object({
    min_capacity = number
    max_capacity = number
    reader_count = optional(number, 0)
  })
  default = null

  validation {
    condition     = var.serverless == null ? true : (var.serverless.min_capacity >= 0 && var.serverless.min_capacity <= var.serverless.max_capacity && var.serverless.max_capacity <= 256)
    error_message = "serverless capacity must satisfy 0 <= min_capacity <= max_capacity <= 256."
  }

  validation {
    condition     = var.serverless == null ? true : (var.serverless.min_capacity * 2 == floor(var.serverless.min_capacity * 2) && var.serverless.max_capacity * 2 == floor(var.serverless.max_capacity * 2))
    error_message = "serverless min_capacity and max_capacity must be multiples of 0.5."
  }

  validation {
    condition     = var.serverless == null ? true : (var.serverless.reader_count >= 0 && var.serverless.reader_count <= 15)
    error_message = "serverless.reader_count must be 0-15."
  }
}

variable "proxy" {
  description = "RDS Proxy；`null` 時不建。`role_arn` 實質必填。欄位見〈`proxy` 欄位〉。"
  type = object({
    security_group_ids           = list(string)
    role_arn                     = optional(string)
    require_tls                  = optional(bool, true)
    idle_client_timeout          = optional(number, 1800)
    max_connections_percent      = optional(number, 50)
    max_idle_connections_percent = optional(number, 25)
    debug_logging                = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.proxy == null ? true : (var.proxy.role_arn != null && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.proxy.role_arn)))
    error_message = "proxy.role_arn is required and must be an IAM role ARN (created in the iam-base stack)."
  }
}

variable "alarm_config" {
  description = "告警門檻。`connections_threshold` 在 `rds`、`aurora` 必填。欄位見〈`alarm_config` 欄位〉。"
  type = object({
    cpu_threshold            = optional(number, 80)
    freeable_memory_bytes    = optional(number, 209715200)
    connections_threshold    = optional(number)
    replica_lag_threshold_ms = optional(number, 1000)
    proxy_borrowed_percent   = optional(number, 80)
    proxy_pinned_percent     = optional(number, 20)
  })
  default = {}

  validation {
    condition     = !contains(["rds", "aurora"], var.deployment) || var.alarm_config.connections_threshold != null
    error_message = "alarm_config.connections_threshold is required for rds and aurora: max_connections depends on the instance class and cannot be derived offline."
  }
}
