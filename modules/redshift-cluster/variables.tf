variable "name" {
  type        = string
  description = "cluster 識別名稱，也是 subnet group 與 parameter group 的名稱。1–63 字元，限小寫英文字母、數字、`-`，開頭要是字母，不能連續兩個 `-` 或以 `-` 結尾。"

  validation {
    condition     = length(var.name) <= 63 && can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name))
    error_message = "name must be 1-63 chars of lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "database_name" {
  type        = string
  description = "cluster 建立的第一個資料庫名稱，1–64 字元，限小寫英文字母、數字、`_`，開頭要是字母。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,63}$", var.database_name))
    error_message = "database_name must be 1-64 chars of lowercase letters, digits and underscores, starting with a letter."
  }
}

variable "master_username" {
  type        = string
  default     = "dbadmin"
  nullable    = false
  description = "管理者帳號名稱（預設 `dbadmin`）。密碼由 Redshift 產生並放在 Secrets Manager，module 沒有密碼變數。"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_+.@$-]{0,127}$", var.master_username))
    error_message = "master_username must be 1-128 chars: lowercase letters, digits and _+.@$-, starting with a letter or underscore."
  }
}

variable "node_type" {
  type        = string
  description = "node 類型，只收 RA3：`ra3.large`、`ra3.xlplus`、`ra3.4xlarge`、`ra3.16xlarge`。"

  validation {
    condition     = contains(["ra3.large", "ra3.xlplus", "ra3.4xlarge", "ra3.16xlarge"], var.node_type)
    error_message = "node_type must be one of ra3.large, ra3.xlplus, ra3.4xlarge, ra3.16xlarge."
  }
}

variable "number_of_nodes" {
  type        = number
  default     = 1
  nullable    = false
  description = "node 數量，1–128（預設 1）。1 個 node 是 single-node cluster，只有 `ra3.large`、`ra3.xlplus` 可以；官方文件不建議 production 用 single-node。每種 node type 的建立上限不同（`ra3.large`、`ra3.xlplus` 16、`ra3.4xlarge` 32），超過會由 AWS 回錯。"

  validation {
    condition     = try(var.number_of_nodes == floor(var.number_of_nodes) && var.number_of_nodes >= 1 && var.number_of_nodes <= 128, false)
    error_message = "number_of_nodes must be a whole number between 1 and 128."
  }

  validation {
    condition     = var.number_of_nodes != 1 || !contains(["ra3.4xlarge", "ra3.16xlarge"], var.node_type)
    error_message = "A single-node cluster is only available for ra3.large and ra3.xlplus; use at least 2 nodes for ra3.4xlarge and ra3.16xlarge."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "cluster 資料與管理者 secret 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 Redshift 能建立 grant（執行 apply 的身分需要 `kms:CreateGrant`）。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "iam_role_arns" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "掛到 cluster 的 IAM role ARN（例如讀 S3 curated、Glue catalog 的 role）。role 由呼叫端建立，這個 module 不建 IAM。"

  validation {
    condition     = alltrue([for a in var.iam_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", a))])
    error_message = "Every iam_role_arns entry must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "default_iam_role_arn" {
  type        = string
  default     = null
  description = "cluster 的預設 IAM role ARN，必須也在 `iam_role_arns` 裡；`null` 表示不設預設 role。"

  validation {
    condition     = var.default_iam_role_arn == null || contains(var.iam_role_arns, var.default_iam_role_arn)
    error_message = "default_iam_role_arn must also be listed in iam_role_arns."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "cluster 的 subnet，至少兩個、分屬不同 AZ（module 只能數 subnet，AZ 分布由呼叫端保證）。"

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) && length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids must be at least 2 distinct subnet ids (subnet-...)."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "cluster 的 security group，至少一個，由 network stack 建立。"

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must hold at least one security group id (sg-...)."
  }
}

variable "enhanced_vpc_routing" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否開 enhanced VPC routing，讓 COPY、UNLOAD 與 Spectrum 的流量走 VPC（預設 `true`）。S3 與 Glue 要有 VPC endpoint 或 NAT。"
}

variable "automated_snapshot_retention_days" {
  type        = number
  default     = 7
  nullable    = false
  description = "自動 snapshot 的保留天數，0–35（預設 7）；0 表示關閉自動 snapshot。"

  validation {
    condition     = try(var.automated_snapshot_retention_days == floor(var.automated_snapshot_retention_days) && var.automated_snapshot_retention_days >= 0 && var.automated_snapshot_retention_days <= 35, false)
    error_message = "automated_snapshot_retention_days must be a whole number between 0 and 35."
  }
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  nullable    = false
  description = "destroy 時是否跳過最終 snapshot（預設 `false`）。不跳過時 snapshot 名稱是 `<name>-final`，同名 snapshot 已存在會讓 destroy 失敗。"
}

variable "multi_az" {
  type        = bool
  default     = false
  nullable    = false
  description = "是否啟用 Multi-AZ（預設 `false`）。官方文件說明 Multi-AZ 支援 RA3 與 RG；實際限制由 AWS 回錯。"
}

variable "parameters" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "額外的 cluster parameter（例如 `datestyle`、`search_path`、`max_concurrency_scaling_clusters`）。`require_ssl` 與 `enable_user_activity_logging` 由 module 管，不能在這裡設。"

  validation {
    condition     = length(setintersection(toset(keys(var.parameters)), toset(["require_ssl", "enable_user_activity_logging"]))) == 0
    error_message = "parameters must not set require_ssl or enable_user_activity_logging; the module owns them."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "cluster、subnet group、parameter group 的 tag；`Name` 由 module 加上。"
}
