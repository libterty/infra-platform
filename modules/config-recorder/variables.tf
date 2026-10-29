variable "name" {
  type        = string
  description = "recorder 與 delivery channel 的名稱，1–256 字元，限英數字、`.`、`_`、`-`。一個 region 只能有一個 recorder，慣例用 `default`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,256}$", var.name))
    error_message = "name must be 1-256 chars of letters, digits, '.', '_' or '-'."
  }
}

variable "role_arn" {
  type        = string
  description = "recorder 用的 IAM role ARN，必填。role 要信任 `config.amazonaws.com`（條件 `aws:SourceAccount`）並掛 AWS managed policy `AWS_ConfigRole`；在範本的 `iam` stack 建，module 不建 IAM。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN."
  }
}

variable "s3_bucket_name" {
  type        = string
  description = "delivery channel 寫入 configuration snapshot 與 history 的 S3 bucket。bucket policy 要允許 `config.amazonaws.com`（`s3-bucket` 0.6.0 的 `log_delivery` 含 `config`）。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_bucket_name))
    error_message = "s3_bucket_name must be a valid S3 bucket name."
  }
}

variable "s3_key_prefix" {
  type        = string
  default     = null
  description = "寫入 bucket 的 key prefix；`null`（預設）寫在 bucket 根目錄的 `AWSLogs/`。"

  validation {
    condition     = var.s3_key_prefix == null || can(regex("^[^/].{0,254}[^/]$|^[^/]$", var.s3_key_prefix))
    error_message = "s3_key_prefix must be 1-256 characters and must not start or end with '/'."
  }
}

variable "s3_kms_key_arn" {
  type        = string
  default     = null
  description = "寫入 S3 時用的客戶管理 KMS key ARN（`key/<id>`，不收 alias）；`null`（預設）用 bucket 的預設加密。key policy 要允許 recorder 的 role 用這把 key。"

  validation {
    condition     = var.s3_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.s3_kms_key_arn))
    error_message = "s3_kms_key_arn must be a KMS key ARN (key/<id>), not an alias."
  }
}

variable "sns_topic_arn" {
  type        = string
  default     = null
  description = "Config 送組態變更與合規通知的 SNS topic ARN；`null`（預設）不送。通知量大，通常不送到告警 topic。"

  validation {
    condition     = var.sns_topic_arn == null || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be an SNS topic ARN."
  }
}

variable "recording" {
  type = object({
    include_global_resource_types = optional(bool, true)
    exclusion_types               = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "記錄範圍。`exclusion_types` 空的（預設）記錄所有支援的 resource type，`include_global_resource_types`（預設 `true`）決定要不要加上 IAM user、group、role、customer managed policy；多個 region 都有 recorder 時只能在一個 region 為 `true`。給 `exclusion_types`（例如 `AWS::EC2::NetworkInterface`）改用排除策略，這時 `include_global_resource_types` 要設 `false`，IAM 類型除非列進排除清單，否則照樣記錄。"

  validation {
    condition     = length(var.recording.exclusion_types) == 0 || !var.recording.include_global_resource_types
    error_message = "recording.exclusion_types requires recording.include_global_resource_types = false; with exclusions the global IAM types are recorded unless listed."
  }

  validation {
    condition     = alltrue([for t in var.recording.exclusion_types : can(regex("^AWS::[A-Za-z0-9]+::[A-Za-z0-9]+$", t))])
    error_message = "recording.exclusion_types must be resource types such as AWS::EC2::NetworkInterface."
  }
}

variable "recording_frequency" {
  type        = string
  default     = "CONTINUOUS"
  nullable    = false
  description = "記錄頻率：`CONTINUOUS`（預設，每次變更都記）或 `DAILY`（每天一次，configuration item 較少、費用較低）。"

  validation {
    condition     = contains(["CONTINUOUS", "DAILY"], var.recording_frequency)
    error_message = "recording_frequency must be CONTINUOUS or DAILY."
  }
}

variable "snapshot_frequency" {
  type        = string
  default     = "TwentyFour_Hours"
  nullable    = false
  description = "configuration snapshot 送到 S3 的頻率：`One_Hour`、`Three_Hours`、`Six_Hours`、`Twelve_Hours`、`TwentyFour_Hours`（預設）。"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.snapshot_frequency)
    error_message = "snapshot_frequency must be One_Hour, Three_Hours, Six_Hours, Twelve_Hours or TwentyFour_Hours."
  }
}

variable "retention_days" {
  type        = number
  default     = 2557
  nullable    = false
  description = "Config 保留 configuration item 的天數，30–2557（預設 2557，約 7 年）。只影響 Config 服務內的歷史，不影響 S3 裡的檔案。"

  validation {
    condition     = var.retention_days == floor(var.retention_days) && var.retention_days >= 30 && var.retention_days <= 2557
    error_message = "retention_days must be a whole number from 30 to 2557."
  }
}

variable "managed_rules" {
  type = map(object({
    input_parameters     = optional(map(string), {})
    scope_resource_types = optional(list(string), [])
  }))
  default     = {}
  nullable    = false
  description = "要啟用的 AWS managed rule，key 是 rule identifier（大寫底線格式，例如 `S3_BUCKET_VERSIONING_ENABLED`），rule 名稱是 identifier 轉小寫加 `-`。`input_parameters` 是 rule 參數；`scope_resource_types` 限定評估的 resource type。FSBP 與 CIS 已由 Security Hub 評估，這裡只放額外需要的 rule。空的（預設）不建 rule。"

  validation {
    condition     = alltrue([for k in keys(var.managed_rules) : can(regex("^[A-Z0-9]+(_[A-Z0-9]+)*$", k))])
    error_message = "managed_rules keys must be AWS managed rule identifiers in upper snake case, such as S3_BUCKET_VERSIONING_ENABLED."
  }
}

variable "aggregator" {
  type = object({
    name                  = string
    account_ids           = optional(list(string), [])
    organization_role_arn = optional(string)
    regions               = optional(list(string), [])
  })
  default     = null
  description = "彙整多帳號或整個 organization 的 Config 資料（選填）。`account_ids` 與 `organization_role_arn` 擇一：前者彙整指定帳號（各帳號要授權），後者在管理帳號或委派管理帳號彙整整個 organization，role 要掛 `AWSConfigRoleForOrganizations`。`regions` 空的（預設）彙整所有 region。`null`（預設）不建。"

  validation {
    condition     = var.aggregator == null || (length(try(var.aggregator.account_ids, [])) > 0) != (try(var.aggregator.organization_role_arn, null) != null)
    error_message = "aggregator needs exactly one of account_ids or organization_role_arn."
  }

  validation {
    condition     = var.aggregator == null || alltrue([for id in try(var.aggregator.account_ids, []) : can(regex("^[0-9]{12}$", id))])
    error_message = "aggregator.account_ids must be 12-digit account IDs."
  }

  validation {
    condition     = try(var.aggregator.organization_role_arn, null) == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.aggregator.organization_role_arn))
    error_message = "aggregator.organization_role_arn must be an IAM role ARN."
  }

  validation {
    condition     = var.aggregator == null || alltrue([for r in try(var.aggregator.regions, []) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "aggregator.regions must be AWS regions such as us-east-1."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "recorder 所在的 region；`null`（預設）用 provider 的 region。Config 是 regional 服務，每個 region 各呼叫一次 module。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "managed rule 與 aggregator 的 tag（recorder 與 delivery channel 不支援 tag）；`Name` 由 module 加上。"
}
