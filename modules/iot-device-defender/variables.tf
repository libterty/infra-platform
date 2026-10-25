variable "account_id" {
  type        = string
  default     = null
  description = "audit 設定所屬的 AWS 帳號 ID（12 位數字）。給 `audit` 時必填，`audit = null` 時不用給。awscc 拿不到呼叫者身分，所以由呼叫端傳入（通常是 `data.aws_caller_identity.current.account_id`）。"

  validation {
    condition     = var.account_id == null ? var.audit == null : can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID, and it is required when audit is given."
  }
}

variable "audit" {
  type = object({
    role_arn = string
    checks   = list(string)
    sns = optional(object({
      target_arn = string
      role_arn   = string
    }))
  })
  default     = null
  description = "帳號層的 Device Defender audit 設定；`null` 不建（同帳號同 region 只能有一份，第二個專案要設 `null`）。`role_arn` 是讓 IoT 讀取設定的 role（要有 `AWSIoTDeviceDefenderAudit` 的權限）；`checks` 是要啟用的 check（API 名稱，例如 `LOGGING_DISABLED_CHECK`），沒列的一律停用；`sns` 給了就把 audit 結果送到 SNS topic（`role_arn` 要能 `sns:Publish`）。"

  validation {
    condition     = var.audit == null || try(length(var.audit.checks) >= 1, false)
    error_message = "audit.checks must list at least one check."
  }

  validation {
    condition = var.audit == null || try(alltrue([for c in var.audit.checks : contains([
      "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK", "CA_CERTIFICATE_EXPIRING_CHECK", "CA_CERTIFICATE_KEY_QUALITY_CHECK",
      "CONFLICTING_CLIENT_IDS_CHECK", "DEVICE_CERTIFICATE_AGE_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK",
      "DEVICE_CERTIFICATE_KEY_QUALITY_CHECK", "DEVICE_CERTIFICATE_SHARED_CHECK", "INTERMEDIATE_CA_REVOKED_FOR_ACTIVE_DEVICE_CERTIFICATES_CHECK",
      "IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK", "IOT_ROLE_ALIAS_ALLOWS_ACCESS_TO_UNUSED_SERVICES_CHECK",
      "IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK", "LOGGING_DISABLED_CHECK", "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK",
      "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK", "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK",
    ], c)]), false)
    error_message = "audit.checks must be audit check API names such as LOGGING_DISABLED_CHECK (see the README for the full list)."
  }

  validation {
    condition     = var.audit == null || try(can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.audit.role_arn)), false)
    error_message = "audit.role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition = var.audit == null || try(var.audit.sns == null || (
      can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]{1,256}$", var.audit.sns.target_arn)) &&
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.audit.sns.role_arn))
    ), false)
    error_message = "audit.sns.target_arn must be an SNS topic ARN and audit.sns.role_arn an IAM role ARN."
  }
}

variable "scheduled_audits" {
  type = map(object({
    frequency    = string
    day_of_week  = optional(string)
    day_of_month = optional(string)
    checks       = list(string)
  }))
  default     = {}
  nullable    = false
  description = "排程稽核，key 是名稱（1–128 字元，限英數字、`_`、`-`）。`frequency` 是 `DAILY`、`WEEKLY`、`BIWEEKLY`、`MONTHLY`；`WEEKLY`、`BIWEEKLY` 要給 `day_of_week`（`SUN`–`SAT`），`MONTHLY` 要給 `day_of_month`（`1`–`31` 或 `LAST`），其他組合不收；`checks` 是這次稽核跑的 check（至少一個）。有給 `audit` 時，`checks` 都要在 `audit.checks` 裡（AWS 不准停用排程在用的 check）。"

  validation {
    condition     = alltrue([for name, _ in var.scheduled_audits : can(regex("^[a-zA-Z0-9_-]{1,128}$", name))])
    error_message = "scheduled audit names must be 1-128 chars of letters, digits, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for _, a in var.scheduled_audits : contains(["DAILY", "WEEKLY", "BIWEEKLY", "MONTHLY"], a.frequency)])
    error_message = "scheduled audit frequency must be DAILY, WEEKLY, BIWEEKLY or MONTHLY."
  }

  validation {
    condition = alltrue([for _, a in var.scheduled_audits : (
      contains(["WEEKLY", "BIWEEKLY"], a.frequency) ? (a.day_of_month == null && contains(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], coalesce(a.day_of_week, "-"))) :
      a.frequency == "MONTHLY" ? (a.day_of_week == null && can(regex("^([1-9]|[12][0-9]|3[01]|LAST)$", coalesce(a.day_of_month, "-")))) :
      (a.day_of_week == null && a.day_of_month == null)
    )])
    error_message = "WEEKLY and BIWEEKLY audits need day_of_week (SUN-SAT) only, MONTHLY audits need day_of_month (1-31 or LAST) only, and DAILY audits take neither."
  }

  validation {
    condition = alltrue([for _, a in var.scheduled_audits : length(a.checks) >= 1 && alltrue([for c in a.checks : contains([
      "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK", "CA_CERTIFICATE_EXPIRING_CHECK", "CA_CERTIFICATE_KEY_QUALITY_CHECK",
      "CONFLICTING_CLIENT_IDS_CHECK", "DEVICE_CERTIFICATE_AGE_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK",
      "DEVICE_CERTIFICATE_KEY_QUALITY_CHECK", "DEVICE_CERTIFICATE_SHARED_CHECK", "INTERMEDIATE_CA_REVOKED_FOR_ACTIVE_DEVICE_CERTIFICATES_CHECK",
      "IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK", "IOT_ROLE_ALIAS_ALLOWS_ACCESS_TO_UNUSED_SERVICES_CHECK",
      "IOT_ROLE_ALIAS_OVERLY_PERMISSIVE_CHECK", "LOGGING_DISABLED_CHECK", "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK",
      "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK", "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK",
    ], c)])])
    error_message = "scheduled audit checks must list at least one audit check API name such as LOGGING_DISABLED_CHECK."
  }

  validation {
    condition     = var.audit == null || alltrue([for _, a in var.scheduled_audits : alltrue([for c in a.checks : contains(try(var.audit.checks, []), c)])])
    error_message = "every check used by a scheduled audit must be enabled in audit.checks; AWS does not allow disabling a check that a scheduled audit uses."
  }
}

variable "mitigation_actions" {
  type = map(object({
    role_arn = string
    add_things_to_thing_group = optional(object({
      thing_group_names       = list(string)
      override_dynamic_groups = optional(bool, false)
    }))
    update_device_certificate = optional(object({
      action = optional(string, "DEACTIVATE")
    }))
    publish_finding_to_sns = optional(object({
      topic_arn = string
    }))
    enable_iot_logging = optional(object({
      role_arn_for_logging = string
      log_level            = string
    }))
  }))
  default     = {}
  nullable    = false
  description = "mitigation action，key 是名稱（1–128 字元，限英數字、`_`、`-`）。`role_arn` 是執行 action 用的 role；以下四種剛好給一種：`add_things_to_thing_group`（把裝置移到隔離用的 thing group，`thing_group_names` 1–10 個）、`update_device_certificate`（停用裝置憑證，`action` 只能是 `DEACTIVATE`）、`publish_finding_to_sns`（`topic_arn`）、`enable_iot_logging`（`role_arn_for_logging` 與 `log_level`：`DEBUG`、`INFO`、`WARN`、`ERROR`）。"

  validation {
    condition     = alltrue([for name, _ in var.mitigation_actions : can(regex("^[a-zA-Z0-9_-]{1,128}$", name))])
    error_message = "mitigation action names must be 1-128 chars of letters, digits, underscores or hyphens."
  }

  validation {
    condition = alltrue([for _, m in var.mitigation_actions : length(compact([
      m.add_things_to_thing_group == null ? "" : "a",
      m.update_device_certificate == null ? "" : "u",
      m.publish_finding_to_sns == null ? "" : "p",
      m.enable_iot_logging == null ? "" : "e",
    ])) == 1])
    error_message = "each mitigation action must set exactly one of add_things_to_thing_group, update_device_certificate, publish_finding_to_sns or enable_iot_logging."
  }

  validation {
    condition     = alltrue([for _, m in var.mitigation_actions : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", m.role_arn))])
    error_message = "mitigation action role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition = alltrue([for _, m in var.mitigation_actions : m.add_things_to_thing_group == null || try(
      length(m.add_things_to_thing_group.thing_group_names) >= 1 && length(m.add_things_to_thing_group.thing_group_names) <= 10 &&
      alltrue([for g in m.add_things_to_thing_group.thing_group_names : can(regex("^[a-zA-Z0-9:_-]{1,128}$", g))])
    , false)])
    error_message = "add_things_to_thing_group.thing_group_names must list 1-10 thing group names (1-128 chars of letters, digits, colons, underscores or hyphens)."
  }

  validation {
    condition     = alltrue([for _, m in var.mitigation_actions : m.update_device_certificate == null || try(m.update_device_certificate.action == "DEACTIVATE", false)])
    error_message = "update_device_certificate.action must be DEACTIVATE."
  }

  validation {
    condition     = alltrue([for _, m in var.mitigation_actions : m.publish_finding_to_sns == null || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]{1,256}$", m.publish_finding_to_sns.topic_arn))])
    error_message = "publish_finding_to_sns.topic_arn must be an SNS topic ARN."
  }

  validation {
    condition = alltrue([for _, m in var.mitigation_actions : m.enable_iot_logging == null || try(
      contains(["DEBUG", "INFO", "WARN", "ERROR"], m.enable_iot_logging.log_level) &&
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", m.enable_iot_logging.role_arn_for_logging))
    , false)])
    error_message = "enable_iot_logging needs log_level DEBUG, INFO, WARN or ERROR and role_arn_for_logging as an IAM role ARN."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "排程稽核與 mitigation action 的 tag；module 轉成 awscc 要的 `{ key, value }` 集合，並加上 `Name`（資源名稱）。帳號層 audit 設定沒有 tag。"
}
