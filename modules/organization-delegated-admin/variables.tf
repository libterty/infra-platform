variable "delegated_admin_account_id" {
  type        = string
  description = "被委派的帳號 ID（12 位數字），通常是資安帳號。必須是 organization 的成員帳號，不能是管理帳號。"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.delegated_admin_account_id))
    error_message = "delegated_admin_account_id must be a 12-digit AWS account ID."
  }
}

variable "services" {
  type        = set(string)
  description = "要委派的服務，至少一個：`guardduty`、`securityhub`、`inspector`、`config`、`access-analyzer`、`cloudtrail`。每個服務會開 trusted access，再用該服務規定的方式委派（見 README）。"

  validation {
    condition     = length(var.services) > 0
    error_message = "services must contain at least one service."
  }

  validation {
    condition     = alltrue([for s in var.services : contains(["guardduty", "securityhub", "inspector", "config", "access-analyzer", "cloudtrail"], s)])
    error_message = "services must be a subset of guardduty, securityhub, inspector, config, access-analyzer and cloudtrail."
  }
}

variable "regions" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "GuardDuty、Security Hub、Inspector 要委派的 region，例如 `[\"ap-northeast-1\", \"us-east-1\"]`；`[]`（預設）只委派 provider 的 region。這三個服務的委派是 regional，trusted access 與其他服務的委派是 organization 全域，只建一次。"

  validation {
    condition     = alltrue([for r in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "regions must look like ap-northeast-1."
  }
}
