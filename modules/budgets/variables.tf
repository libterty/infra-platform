variable "budgets" {
  type = map(object({
    limit_amount = number
    time_unit    = optional(string, "MONTHLY")
    cost_filters = optional(map(list(string)), {})
    notifications = optional(list(object({
      comparison     = optional(string, "GREATER_THAN")
      threshold      = number
      threshold_type = optional(string, "PERCENTAGE")
      type           = string
      sns_topic_arns = optional(list(string), [])
      emails         = optional(list(string), [])
    })), [])
  }))
  description = "成本預算，key 是預算名稱（1–100 字元，不含 `:` 與 `\\`）。`limit_amount` 是美元金額（正數）；`time_unit` 是 `DAILY`、`MONTHLY`（預設）、`QUARTERLY`、`ANNUALLY`；`cost_filters` 是 filter 名稱對值清單，例如 `{ Service = [\"Amazon Elastic Compute Cloud - Compute\"] }`。`notifications` 每個：`comparison` 是 `GREATER_THAN`（預設）、`LESS_THAN`、`EQUAL_TO`；`threshold_type` 是 `PERCENTAGE`（預設，`threshold` 0–1000）或 `ABSOLUTE_VALUE`（`threshold` 是美元金額）；`type` 是 `ACTUAL` 或 `FORECASTED`；`sns_topic_arns` 最多 1 個、`emails` 最多 10 個，兩者合計至少 1 個。"

  validation {
    condition     = alltrue([for k, _ in var.budgets : can(regex("^[^:\\\\]{1,100}$", k))])
    error_message = "budget names must be 1-100 chars without ':' or '\\'."
  }

  validation {
    condition     = alltrue([for _, b in var.budgets : b.limit_amount > 0])
    error_message = "budget limit_amount must be a positive USD amount."
  }

  validation {
    condition     = alltrue([for _, b in var.budgets : contains(["DAILY", "MONTHLY", "QUARTERLY", "ANNUALLY"], b.time_unit)])
    error_message = "budget time_unit must be DAILY, MONTHLY, QUARTERLY or ANNUALLY."
  }

  validation {
    condition = alltrue(flatten([for _, b in var.budgets : [for n in b.notifications :
      contains(["GREATER_THAN", "LESS_THAN", "EQUAL_TO"], n.comparison) &&
      contains(["PERCENTAGE", "ABSOLUTE_VALUE"], n.threshold_type) &&
      contains(["ACTUAL", "FORECASTED"], n.type)
    ]]))
    error_message = "notification comparison must be GREATER_THAN, LESS_THAN or EQUAL_TO, threshold_type PERCENTAGE or ABSOLUTE_VALUE, and type ACTUAL or FORECASTED."
  }

  validation {
    condition = alltrue(flatten([for _, b in var.budgets : [for n in b.notifications :
      n.threshold >= 0 && (n.threshold_type != "PERCENTAGE" || n.threshold <= 1000)
    ]]))
    error_message = "notification threshold must be 0-1000 for PERCENTAGE and not negative for ABSOLUTE_VALUE."
  }

  validation {
    condition = alltrue(flatten([for _, b in var.budgets : [for n in b.notifications :
      length(n.sns_topic_arns) + length(n.emails) >= 1 && length(n.sns_topic_arns) <= 1 && length(n.emails) <= 10
    ]]))
    error_message = "each notification needs at least one subscriber, with at most one SNS topic and at most 10 email addresses."
  }

  validation {
    condition = alltrue(flatten([for _, b in var.budgets : [for n in b.notifications : [
      for a in n.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]{1,256}$", a))
    ]]]))
    error_message = "notification sns_topic_arns must be standard SNS topic ARNs (arn:<partition>:sns:<region>:<account>:<name>)."
  }

  validation {
    condition = alltrue(flatten([for _, b in var.budgets : [for n in b.notifications : [
      for e in n.emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))
    ]]]))
    error_message = "notification emails must be email addresses."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個預算的 tag；`Name` 由 module 加上（預算名稱）。"
}
