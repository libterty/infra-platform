variable "name_prefix" {
  type        = string
  description = "Rule and group names are <name_prefix>-<key>; X-Ray limits both to 32 characters."
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
  description = "Sampling rules keyed by short name. priority is 1-9999 (lower wins), fixed_rate is 0-1, reservoir_size is traces per second sampled before fixed_rate applies."

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
  description = "X-Ray groups keyed by short name, for example fault = true OR error = true, or responsetime > 3."

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
  description = "Tags applied to every rule and group."
}
