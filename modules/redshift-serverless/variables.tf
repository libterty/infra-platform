variable "name" {
  type        = string
  description = "namespace 與 workgroup 共用的名稱，3–64 字元，限小寫英文字母、數字、`-`。"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,64}$", var.name))
    error_message = "name must be 3-64 chars of lowercase letters, digits and hyphens."
  }
}

variable "db_name" {
  type        = string
  description = "namespace 建立的第一個資料庫名稱，1–64 字元，限小寫英文字母、數字、`_`，開頭要是字母。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must be 1-64 chars of lowercase letters, digits and underscores, starting with a letter."
  }
}

variable "admin_username" {
  type        = string
  default     = "dbadmin"
  nullable    = false
  description = "管理者帳號名稱（預設 `dbadmin`）。密碼由 Redshift 產生並放在 Secrets Manager，module 沒有密碼變數。"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_+.@$-]{0,127}$", var.admin_username))
    error_message = "admin_username must be 1-128 chars: lowercase letters, digits and _+.@$-, starting with a letter or underscore."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "namespace 資料與管理者 secret 加密用的客戶管理 KMS key ARN，必填。key policy 要讓 Redshift 能建立 grant（執行 apply 的身分需要 `kms:CreateGrant`）。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "iam_role_arns" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "掛到 namespace 的 IAM role ARN（例如讀 S3 curated、Glue catalog 的 role）。role 由呼叫端建立，這個 module 不建 IAM。"

  validation {
    condition     = alltrue([for a in var.iam_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", a))])
    error_message = "Every iam_role_arns entry must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "default_iam_role_arn" {
  type        = string
  default     = null
  description = "namespace 的預設 IAM role ARN，必須也在 `iam_role_arns` 裡；`null` 表示不設預設 role。"

  validation {
    condition     = var.default_iam_role_arn == null || contains(var.iam_role_arns, var.default_iam_role_arn)
    error_message = "default_iam_role_arn must also be listed in iam_role_arns."
  }
}

variable "base_capacity" {
  type        = number
  default     = 4
  nullable    = false
  description = "workgroup 的 base 容量（RPU），可以是 4，或 8–512 之間 8 的倍數（預設 4）。4 RPU 建議資料量 32 TB、每張表 100 欄以內；擴到 8 以上就不會自動縮回 4。"

  validation {
    condition     = var.base_capacity == 4 || (var.base_capacity >= 8 && var.base_capacity <= 512 && var.base_capacity % 8 == 0)
    error_message = "base_capacity must be 4, or a multiple of 8 between 8 and 512."
  }
}

variable "max_capacity" {
  type        = number
  default     = null
  description = "workgroup 自動擴充的容量上限（RPU），整數、不小於 `base_capacity`、最多 512；`null` 表示不設上限。"

  validation {
    condition     = var.max_capacity == null || try(var.max_capacity == floor(var.max_capacity) && var.max_capacity >= var.base_capacity && var.max_capacity <= 512, false)
    error_message = "max_capacity must be a whole number between base_capacity and 512, or null."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "workgroup 的 subnet。沒開 `enhanced_vpc_routing` 至少 2 個、開了至少 3 個，而且要分屬不同 AZ（module 只能數 subnet，AZ 分布由呼叫端保證）；每個 subnet 要有足夠的空閒 IP（4 RPU 約 9 個）。"

  validation {
    condition = (
      alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) &&
      length(distinct(var.subnet_ids)) >= (var.enhanced_vpc_routing ? 3 : 2)
    )
    error_message = "subnet_ids must be subnet ids, with at least 3 distinct subnets when enhanced_vpc_routing is true and at least 2 otherwise."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "workgroup 的 security group，至少一個，由 network stack 建立。"

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must hold at least one security group id (sg-...)."
  }
}

variable "enhanced_vpc_routing" {
  type        = bool
  default     = true
  nullable    = false
  description = "是否開 enhanced VPC routing，讓 COPY、UNLOAD 與 Spectrum 的流量走 VPC（預設 `true`）。開了需要 3 個 subnet 跨 3 個 AZ，S3 與 Glue 要有 VPC endpoint 或 NAT。"
}

variable "log_exports" {
  type        = set(string)
  default     = ["connectionlog", "userlog", "useractivitylog"]
  nullable    = false
  description = "匯出到 CloudWatch Logs 的稽核 log 類型，至少一個，可選 `connectionlog`、`userlog`、`useractivitylog`（預設全開）。含 `useractivitylog` 時 module 會自動設 `enable_user_activity_logging = true`。"

  validation {
    condition     = length(var.log_exports) >= 1 && alltrue([for l in var.log_exports : contains(["connectionlog", "userlog", "useractivitylog"], l)])
    error_message = "log_exports must hold at least one of connectionlog, userlog, useractivitylog."
  }
}

variable "usage_limit_rpu_hours" {
  type        = number
  default     = null
  description = "每月可用的 RPU-小時上限，必須大於 0；達到上限會 `deactivate`（停止查詢，直到下個月或調高上限）。`null` 表示不設用量上限。"

  validation {
    condition     = var.usage_limit_rpu_hours == null || try(var.usage_limit_rpu_hours > 0, false)
    error_message = "usage_limit_rpu_hours must be greater than 0, or null for no limit."
  }
}

variable "config_parameters" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "額外的 workgroup config parameter（例如 `datestyle`、`search_path`、`max_query_execution_time`）。`require_ssl` 與 `enable_user_activity_logging` 由 module 管，不能在這裡設。"

  validation {
    condition     = length(setintersection(toset(keys(var.config_parameters)), toset(["require_ssl", "enable_user_activity_logging"]))) == 0
    error_message = "config_parameters must not set require_ssl or enable_user_activity_logging; the module owns them."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "namespace 與 workgroup 的 tag；`Name` 由 module 加上。"
}
