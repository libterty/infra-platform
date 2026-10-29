variable "features" {
  type = map(object({
    status                   = string
    additional_configuration = optional(map(string), {})
  }))
  default = {
    S3_DATA_EVENTS         = { status = "ENABLED" }
    EKS_AUDIT_LOGS         = { status = "ENABLED" }
    EBS_MALWARE_PROTECTION = { status = "ENABLED" }
    RDS_LOGIN_EVENTS       = { status = "ENABLED" }
    LAMBDA_NETWORK_LOGS    = { status = "ENABLED" }
    RUNTIME_MONITORING     = { status = "DISABLED" }
  }
  nullable    = false
  description = "detector 的防護功能，key 是 feature 名稱：`S3_DATA_EVENTS`、`EKS_AUDIT_LOGS`、`EBS_MALWARE_PROTECTION`、`RDS_LOGIN_EVENTS`、`LAMBDA_NETWORK_LOGS`、`RUNTIME_MONITORING`。`status` 是 `ENABLED` 或 `DISABLED`；`additional_configuration` 是名稱 → status，只有 `RUNTIME_MONITORING` 能給，名稱限 `EKS_ADDON_MANAGEMENT`、`ECS_FARGATE_AGENT_MANAGEMENT`、`EC2_AGENT_MANAGEMENT`（讓 GuardDuty 自動裝 agent）。預設開 runtime monitoring 以外的五項。只列出的 feature 由 module 管理。"

  validation {
    condition = alltrue([for name, _ in var.features : contains([
      "S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS", "RUNTIME_MONITORING",
    ], name)])
    error_message = "features keys must be S3_DATA_EVENTS, EKS_AUDIT_LOGS, EBS_MALWARE_PROTECTION, RDS_LOGIN_EVENTS, LAMBDA_NETWORK_LOGS or RUNTIME_MONITORING."
  }

  validation {
    condition = alltrue(flatten([for _, f in var.features : concat(
      [contains(["ENABLED", "DISABLED"], f.status)],
      [for _, s in f.additional_configuration : contains(["ENABLED", "DISABLED"], s)],
    )]))
    error_message = "features status and additional_configuration values must be ENABLED or DISABLED."
  }

  validation {
    condition = alltrue(flatten([for name, f in var.features : [for c, _ in f.additional_configuration :
      name == "RUNTIME_MONITORING" && contains(["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT"], c)
    ]]))
    error_message = "additional_configuration is only allowed on RUNTIME_MONITORING, with EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT or EC2_AGENT_MANAGEMENT."
  }
}

variable "finding_publishing_frequency" {
  type        = string
  default     = "FIFTEEN_MINUTES"
  nullable    = false
  description = "finding 更新送到 EventBridge 與 Security Hub 的頻率：`FIFTEEN_MINUTES`（預設）、`ONE_HOUR`、`SIX_HOURS`。新 finding 約 5 分鐘內送出，這個值只影響既有 finding 的更新。"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "finding_publishing_frequency must be FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "organization" {
  type = object({
    auto_enable = string
    features = optional(map(object({
      auto_enable              = string
      additional_configuration = optional(map(string), {})
    })), {})
  })
  default     = null
  description = "organization 的自動啟用設定，只在 GuardDuty 的委派管理帳號給。`auto_enable` 是成員帳號自動啟用 GuardDuty 的範圍：`ALL`（含既有成員）、`NEW`（只有新加入的）、`NONE`。`features` 是 feature 名稱 → `{ auto_enable, additional_configuration }`，名稱與 `features` 相同，`auto_enable` 與 `additional_configuration` 的值也是 `ALL`、`NEW`、`NONE`。`null`（預設）時不管理 organization 設定。"

  validation {
    condition     = var.organization == null || contains(["ALL", "NEW", "NONE"], try(var.organization.auto_enable, ""))
    error_message = "organization.auto_enable must be ALL, NEW or NONE."
  }

  validation {
    condition = var.organization == null || alltrue([for name, _ in try(var.organization.features, {}) : contains([
      "S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS", "RUNTIME_MONITORING",
    ], name)])
    error_message = "organization.features keys must be S3_DATA_EVENTS, EKS_AUDIT_LOGS, EBS_MALWARE_PROTECTION, RDS_LOGIN_EVENTS, LAMBDA_NETWORK_LOGS or RUNTIME_MONITORING."
  }

  validation {
    condition = var.organization == null || alltrue(flatten([for _, f in try(var.organization.features, {}) : concat(
      [contains(["ALL", "NEW", "NONE"], f.auto_enable)],
      [for _, s in f.additional_configuration : contains(["ALL", "NEW", "NONE"], s)],
    )]))
    error_message = "organization.features auto_enable and additional_configuration values must be ALL, NEW or NONE."
  }

  validation {
    condition = var.organization == null || alltrue(flatten([for name, f in try(var.organization.features, {}) : [for c, _ in f.additional_configuration :
      name == "RUNTIME_MONITORING" && contains(["EKS_ADDON_MANAGEMENT", "ECS_FARGATE_AGENT_MANAGEMENT", "EC2_AGENT_MANAGEMENT"], c)
    ]]))
    error_message = "organization additional_configuration is only allowed on RUNTIME_MONITORING, with EKS_ADDON_MANAGEMENT, ECS_FARGATE_AGENT_MANAGEMENT or EC2_AGENT_MANAGEMENT."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "detector 所在的 region；`null`（預設）用 provider 的 region。GuardDuty 是 regional 服務，每個 region 各呼叫一次。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as ap-northeast-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "detector 的 tag。"
}
