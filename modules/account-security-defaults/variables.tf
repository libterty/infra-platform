variable "region" {
  type        = string
  default     = null
  description = "EBS 預設加密、EBS 預設 key 與 IMDS 預設值所在的 region；`null`（預設）用 provider 的 region。S3 account public access block 與密碼政策是帳號全域設定，不受影響。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}

variable "s3_public_access_block" {
  type        = bool
  default     = true
  nullable    = false
  description = "`true` 管理帳號層的 S3 public access block，四項全開。`false` 不管理，帳號原本的設定不變；從 `true` 改成 `false` 會移除這項設定。一個帳號只能有一份，第二個 region 呼叫時給 `false`。"
}

variable "ebs_encryption_by_default" {
  type        = bool
  default     = true
  nullable    = false
  description = "`true` 在這個 region 開 EBS 預設加密。`false` 不管理，原本的設定不變；從 `true` 改成 `false` 會關掉預設加密。"
}

variable "ebs_default_kms_key_arn" {
  type        = string
  default     = null
  description = "EBS 預設加密用的客戶管理 KMS key ARN（`arn:aws:kms:<region>:<帳號>:key/<id>`）。`null` 用 AWS 管理的 `aws/ebs`。要有 `ebs_encryption_by_default = true`。"

  validation {
    condition     = var.ebs_default_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.ebs_default_kms_key_arn))
    error_message = "ebs_default_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases are not accepted."
  }

  validation {
    condition     = var.ebs_default_kms_key_arn == null || var.ebs_encryption_by_default
    error_message = "ebs_default_kms_key_arn requires ebs_encryption_by_default = true."
  }
}

variable "imdsv2_default" {
  type        = bool
  default     = true
  nullable    = false
  description = "`true` 把這個 region 新 instance 的 IMDS 預設值設成 `http_tokens = \"required\"`（IMDSv2）、`http_put_response_hop_limit = 2`。`false` 不管理。只影響之後建立的 instance。"
}

variable "password_policy" {
  type = object({
    minimum_length        = optional(number, 14)
    require_symbols       = optional(bool, true)
    require_numbers       = optional(bool, true)
    require_uppercase     = optional(bool, true)
    require_lowercase     = optional(bool, true)
    max_age_days          = optional(number, 90)
    reuse_prevention      = optional(number, 24)
    allow_users_to_change = optional(bool, true)
  })
  default     = {}
  description = "IAM 使用者的密碼政策（帳號全域）。欄位：`minimum_length`（14–128，預設 14）、`require_symbols`、`require_numbers`、`require_uppercase`、`require_lowercase`（預設都是 `true`）、`max_age_days`（1–1095，預設 90）、`reuse_prevention`（1–24，預設 24）、`allow_users_to_change`（預設 `true`）。`null` 不管理；一個帳號只能有一份，第二個 region 呼叫時給 `null`。"

  validation {
    condition     = var.password_policy == null ? true : (var.password_policy.minimum_length >= 14 && var.password_policy.minimum_length <= 128)
    error_message = "password_policy.minimum_length must be between 14 and 128."
  }

  validation {
    condition     = var.password_policy == null ? true : (var.password_policy.reuse_prevention >= 1 && var.password_policy.reuse_prevention <= 24)
    error_message = "password_policy.reuse_prevention must be between 1 and 24."
  }

  validation {
    condition     = var.password_policy == null ? true : (var.password_policy.max_age_days >= 1 && var.password_policy.max_age_days <= 1095)
    error_message = "password_policy.max_age_days must be between 1 and 1095."
  }
}
