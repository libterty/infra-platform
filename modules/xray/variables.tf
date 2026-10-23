variable "name_prefix" {
  type        = string
  description = "rule 與 group 的名稱前綴，名稱是 `<name_prefix>-<key>`，X-Ray 限制總長最多 32 字元。"
}

variable "sampling_rules" {
  type = map(object({
    priority       = number
    fixed_rate     = number
    reservoir_size = optional(number, 1)
    service_name   = optional(string, "*")
    service_type   = optional(string, "*")
    host           = optional(string, "*")
    http_method    = optional(string, "*")
    url_path       = optional(string, "*")
    attributes     = optional(map(string), {})
  }))
  default     = {}
  description = "sampling rule，key 是 rule 短名。欄位：`priority`（必填，1–9999，越小越先套用，不可重複）、`fixed_rate`（必填，0–1）、`reservoir_size`（每秒先抽的 trace 數，超過才套用 `fixed_rate`，預設 `1`，不得為負）、`service_name`、`service_type`、`host`、`http_method`、`url_path`（預設都是 `*`）、`attributes`（預設 `{}`）。"

  validation {
    condition = alltrue([for k, v in var.sampling_rules :
      length("${var.name_prefix}-${k}") <= 32 &&
      v.priority >= 1 && v.priority <= 9999 &&
      v.fixed_rate >= 0 && v.fixed_rate <= 1 &&
      v.reservoir_size >= 0
    ])
    error_message = "Rule names must fit 32 chars; priority 1-9999; fixed_rate 0-1; reservoir_size >= 0."
  }

  validation {
    condition     = length(distinct([for v in var.sampling_rules : v.priority])) == length(var.sampling_rules)
    error_message = "Each sampling rule must have a unique priority; the evaluation order of equal priorities is undefined."
  }
}

variable "groups" {
  type = map(object({
    filter_expression     = string
    insights_enabled      = optional(bool, false)
    notifications_enabled = optional(bool, false)
  }))
  default     = {}
  description = "X-Ray group，key 是 group 短名。欄位：`filter_expression`（必填，不可為空白，例如 `fault = true OR error = true`、`responsetime > 3`）、`insights_enabled`（預設 `false`）、`notifications_enabled`（預設 `false`，為 `true` 時 `insights_enabled` 也必須是 `true`）。"

  validation {
    condition = alltrue([for k, v in var.groups :
      length("${var.name_prefix}-${k}") <= 32 && length(trimspace(v.filter_expression)) > 0
    ])
    error_message = "Group names must fit 32 chars and filter_expression must not be empty."
  }

  validation {
    condition     = alltrue([for v in var.groups : v.insights_enabled || !v.notifications_enabled])
    error_message = "notifications_enabled requires insights_enabled to be true."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "套用到每個 rule 與 group 的 tag。"
}
