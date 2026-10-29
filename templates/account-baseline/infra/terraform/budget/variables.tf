variable "monthly_budget_usd" {
  description = "每月成本預算（美元）。範本的值是佔位，照帳號的實際用量調整。"
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be a positive USD amount."
  }
}

variable "budget_emails" {
  description = "預算通知的 email，最多 10 個；同一份通知也會送到資安告警 topic。"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.budget_emails) <= 10 && alltrue([for e in var.budget_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "budget_emails must be at most 10 email addresses."
  }
}
