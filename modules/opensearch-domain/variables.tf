variable "name" {
  type        = string
  description = "domain 名稱：3–28 字元，小寫英文字母開頭，只含小寫英文字母、數字與 `-`。同一個帳號同一個 region 內不可重複。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,27}$", var.name))
    error_message = "name must be 3-28 chars, start with a lowercase letter and contain only lowercase letters, digits and hyphens."
  }
}

variable "engine_version" {
  type        = string
  description = "引擎版本，格式 `OpenSearch_<主版號>.<次版號>`，例如 `OpenSearch_2.19`。UltraWarm 與 cold storage 需要 OpenSearch 或 Elasticsearch 7.9 以上；module 只收 OpenSearch。"

  validation {
    condition     = can(regex("^OpenSearch_[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like OpenSearch_2.19; Elasticsearch versions are not accepted."
  }
}

variable "hot" {
  type = object({
    instance_type  = string
    instance_count = number
    ebs = object({
      volume_size = number
      volume_type = optional(string, "gp3")
      iops        = optional(number)
      throughput  = optional(number)
    })
  })
  description = "hot（data）節點：`instance_type`（`.search` 結尾）、`instance_count`（至少 2，且不少於 `availability_zone_count`）、`ebs`（`volume_size` 單位 GiB；`volume_type` 預設 `gp3`，可選 `gp2`、`io1`；`iops`、`throughput` 選填）。啟用 `warm` 時不能用 T2／T3。"

  validation {
    condition     = endswith(var.hot.instance_type, ".search")
    error_message = "hot.instance_type must end with .search (for example m7g.large.search)."
  }

  validation {
    condition     = var.hot.instance_count > 1 && var.hot.instance_count >= var.availability_zone_count && var.hot.instance_count == floor(var.hot.instance_count)
    error_message = "hot.instance_count must be a whole number greater than 1 and not smaller than availability_zone_count."
  }

  validation {
    condition     = contains(["gp3", "gp2", "io1"], var.hot.ebs.volume_type) && var.hot.ebs.volume_size >= 1
    error_message = "hot.ebs.volume_type must be gp3, gp2 or io1 and hot.ebs.volume_size must be at least 1 GiB."
  }
}

variable "dedicated_master" {
  type = object({
    instance_type = string
    count         = number
  })
  default     = null
  description = "dedicated master 節點：`instance_type`（`.search` 結尾）、`count`（3，或 5 以上；不能是 2、4）。`null` 表示不用 dedicated master；啟用 `warm` 時必填。"

  validation {
    condition     = var.dedicated_master == null ? true : endswith(var.dedicated_master.instance_type, ".search")
    error_message = "dedicated_master.instance_type must end with .search."
  }

  validation {
    condition     = var.dedicated_master == null ? true : (var.dedicated_master.count == 3 || (var.dedicated_master.count >= 5 && var.dedicated_master.count == floor(var.dedicated_master.count)))
    error_message = "dedicated_master.count must be 3 or a whole number of 5 or more (2 and 4 are rejected by the service)."
  }
}

variable "warm" {
  type = object({
    instance_type = string
    count         = number
  })
  default     = null
  description = "UltraWarm 節點：`instance_type`（`ultrawarm1.medium.search`、`ultrawarm1.large.search`、`ultrawarm1.xlarge.search`）、`count`（至少 1）。`null` 表示不用。要有 `dedicated_master`，hot 不能是 T2／T3，`multi_az_with_standby` 開啟時 `count` 要是 `availability_zone_count` 的倍數。"

  validation {
    condition     = var.warm == null ? true : can(regex("^ultrawarm1\\.(medium|large|xlarge)\\.search$", var.warm.instance_type))
    error_message = "warm.instance_type must be ultrawarm1.medium.search, ultrawarm1.large.search or ultrawarm1.xlarge.search."
  }

  validation {
    condition     = var.warm == null ? true : (var.warm.count >= 1 && var.warm.count == floor(var.warm.count))
    error_message = "warm.count must be a whole number of at least 1."
  }

  validation {
    condition     = var.warm == null ? true : var.dedicated_master != null
    error_message = "warm requires dedicated_master: UltraWarm only works on domains with dedicated master nodes."
  }

  validation {
    condition     = var.warm == null ? true : !can(regex("^t[23]\\.", var.hot.instance_type))
    error_message = "warm cannot be used when hot.instance_type is a T2 or T3 type."
  }

  validation {
    condition     = var.warm == null ? true : (!var.multi_az_with_standby || var.warm.count % var.availability_zone_count == 0)
    error_message = "with multi_az_with_standby, warm.count must be a multiple of availability_zone_count."
  }
}

variable "cold_storage" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否啟用 cold storage。必須同時有 `warm`。停用前要先刪除或搬回所有 cold index。"

  validation {
    condition     = !var.cold_storage || var.warm != null
    error_message = "cold_storage requires warm: cold storage can only be enabled together with UltraWarm."
  }
}

variable "availability_zone_count" {
  type        = number
  default     = 2
  nullable    = false
  description = "使用的 AZ 數，2 或 3。`subnet_ids` 的數量要跟它相同。"

  validation {
    condition     = contains([2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 2 or 3."
  }
}

variable "multi_az_with_standby" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否啟用 Multi-AZ with Standby。開啟時 `warm.count` 要是 `availability_zone_count` 的倍數，AWS 也要求 dedicated master 與 3 個 AZ 的資料節點配置（module 只檢查文件明寫的倍數條件）。"
}

variable "subnet_ids" {
  type        = list(string)
  description = "domain 所在的 subnet ID，每個 AZ 一個，數量要等於 `availability_zone_count`。domain 一律在 VPC 內，沒有 public 選項。"

  validation {
    condition     = length(var.subnet_ids) == var.availability_zone_count && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids must hold exactly availability_zone_count subnet IDs (subnet-...)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "domain 的 security group ID，至少一個。SG 由呼叫端用 `security-group` module 建，這個 module 不建 SG。"

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "security_group_ids must hold at least one security group ID (sg-...)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "domain 靜態加密與 log group 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 OpenSearch 與 CloudWatch Logs 能用這把 key。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "master_user_secret_arn" {
  type        = string
  description = "master user 帳密所在的 Secrets Manager secret ARN；secret 的值是 JSON `{\"username\": \"...\", \"password\": \"...\"}`。module 用 data source 讀取，沒有密碼變數。密碼會因此留在 state（見 README〈注意〉）。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.master_user_secret_arn))
    error_message = "master_user_secret_arn must be a Secrets Manager secret ARN (arn:<partition>:secretsmanager:<region>:<account>:secret:<name>)."
  }
}

variable "access_principal_arns" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "domain access policy 允許的 IAM role 或 user ARN（用 SigV4 簽章的呼叫端，例如 Firehose 的 role）。不收 `*` 與萬用字元；空的表示不設 access policy。HTTP basic auth 不經過這份 policy，只受 FGAC 控制。"

  validation {
    condition     = alltrue([for p in var.access_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]+$", p))])
    error_message = "access_principal_arns must be IAM role or user ARNs without wildcards; * is not accepted."
  }
}

variable "log_types" {
  type        = set(string)
  default     = ["ES_APPLICATION_LOGS", "AUDIT_LOGS"]
  nullable    = false
  description = "要送到 CloudWatch Logs 的 log 類型（`ES_APPLICATION_LOGS`、`AUDIT_LOGS`、`SEARCH_SLOW_LOGS`、`INDEX_SLOW_LOGS`），每種一個 log group，至少一種。`AUDIT_LOGS` 還要在 Dashboards 開啟稽核設定才會有內容。"

  validation {
    condition     = length(var.log_types) >= 1 && alltrue([for t in var.log_types : contains(["ES_APPLICATION_LOGS", "AUDIT_LOGS", "SEARCH_SLOW_LOGS", "INDEX_SLOW_LOGS"], t)])
    error_message = "log_types must hold at least one of ES_APPLICATION_LOGS, AUDIT_LOGS, SEARCH_SLOW_LOGS, INDEX_SLOW_LOGS."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  nullable    = false
  description = "log group 的保留天數，必須是 CloudWatch Logs 支援的值（1、3、5、7、14、30、60、90、120、150、180、365、400、545、731、1096、1827、2192、2557、2922、3288、3653）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention value CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }
}

variable "auto_tune" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否啟用 Auto-Tune。T2／T3 等小型 instance 不支援。"
}

variable "off_peak_window_start" {
  type        = number
  default     = null
  description = "off-peak window 的起始小時（UTC，0–23），window 長 10 小時。`null` 表示不設定，沿用服務預設。"

  validation {
    condition     = var.off_peak_window_start == null ? true : (var.off_peak_window_start >= 0 && var.off_peak_window_start <= 23 && var.off_peak_window_start == floor(var.off_peak_window_start))
    error_message = "off_peak_window_start must be a whole hour between 0 and 23 (UTC)."
  }
}

variable "automated_snapshot_start_hour" {
  type        = number
  default     = null
  description = "自動快照的起始小時（UTC，0–23）。`null` 表示不設定；OpenSearch 5.3 以上的 domain 每小時自動快照，這個值會被服務忽略。"

  validation {
    condition     = var.automated_snapshot_start_hour == null ? true : (var.automated_snapshot_start_hour >= 0 && var.automated_snapshot_start_hour <= 23 && var.automated_snapshot_start_hour == floor(var.automated_snapshot_start_hour))
    error_message = "automated_snapshot_start_hour must be a whole hour between 0 and 23 (UTC)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "資源的 tag；`Name` 由 module 加上。"
}
