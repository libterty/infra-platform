variable "name_prefix" {
  type        = string
  description = "filter 與 alarm 的名稱前綴，名稱是 `<name_prefix>-<key 的 _ 換成 ->`。小寫字母開頭，2–101 個小寫英數字或連字號。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,100}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits or hyphens."
  }
}

variable "log_group_name" {
  type        = string
  description = "metric filter 讀取的 log group 名稱。"
}

variable "namespace" {
  type        = string
  description = "自訂指標的 namespace，例如 `Alpha/dev`。1–255 字元，不可以 `AWS/` 開頭。"
  validation {
    condition     = can(regex("^[A-Za-z0-9._/#:-]{1,255}$", var.namespace)) && !startswith(var.namespace, "AWS/")
    error_message = "namespace must be 1-255 valid characters and must not start with AWS/."
  }
}

variable "alarms" {
  type = map(object({
    pattern             = string
    metric_name         = string
    description         = string
    metric_value        = optional(string, "1")
    default_value       = optional(number, 0)
    statistic           = optional(string, "Sum")
    period              = optional(number, 60)
    evaluation_periods  = optional(number, 1)
    datapoints_to_alarm = optional(number)
    threshold           = optional(number, 1)
    comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
    treat_missing_data  = optional(string, "notBreaching")
  }))
  default     = {}
  description = "key（snake_case）對應一組 metric filter 加 alarm；非空時必須給 `sns_topic_arns`，key 不可與 `metrics` 重複。欄位見〈`alarms` 欄位〉。"
  validation {
    condition     = alltrue([for k, v in var.alarms : can(regex("^[a-z][a-z0-9_]*$", k)) && length(trimspace(v.pattern)) > 0 && length(trimspace(v.description)) > 0])
    error_message = "Keys must be snake_case; pattern and description must not be empty."
  }
  validation {
    condition = alltrue([for v in values(var.alarms) :
      contains(["Sum", "Average", "Maximum", "Minimum", "SampleCount"], v.statistic) &&
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], v.comparison_operator) &&
      contains(["missing", "ignore", "breaching", "notBreaching"], v.treat_missing_data) &&
      (v.period == 10 || v.period == 30 || v.period % 60 == 0) &&
      (v.datapoints_to_alarm == null ? true : v.datapoints_to_alarm <= v.evaluation_periods)
    ])
    error_message = "Use a supported statistic, comparison operator and treat_missing_data; period must be 10, 30 or a multiple of 60; datapoints_to_alarm must not exceed evaluation_periods."
  }
}

variable "metrics" {
  type = map(object({
    pattern       = string
    metric_name   = string
    metric_value  = optional(string, "1")
    default_value = optional(number, 0)
  }))
  default     = {}
  description = "只建 metric filter、不建 alarm 的項目，給 dashboard 或在別處管理的告警用。key（snake_case）對應 `pattern`（必填，不可為空白）、`metric_name`（必填），以及 `metric_value`（預設 `\"1\"`）、`default_value`（預設 `0`）；key 不可與 `alarms` 重複。`alarms`、`metrics`、`sns_topic_arns` 不可全空。"
  validation {
    condition     = alltrue([for k, v in var.metrics : can(regex("^[a-z][a-z0-9_]*$", k)) && length(trimspace(v.pattern)) > 0])
    error_message = "Keys must be snake_case; pattern must not be empty."
  }
  validation {
    condition     = length(setintersection(toset(keys(var.alarms)), toset(keys(var.metrics)))) == 0
    error_message = "A key cannot be in both alarms and metrics."
  }
  # alarms = {} with sns_topic_arns set stays valid and creates nothing, as in 0.1.0; only a call with no alarms, no metrics and no topics is rejected.
  validation {
    condition     = length(var.alarms) + length(var.metrics) > 0 || length(var.sns_topic_arns) > 0
    error_message = "Give alarms or metrics; the module has nothing to create."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  default     = []
  description = "`alarms` 非空時必填，至少一個。SNS topic ARN，同時用於每個 alarm 的 `alarm_actions` 與 `ok_actions`；只給 `metrics` 時可不給。"
  validation {
    condition     = length(var.alarms) == 0 || length(var.sns_topic_arns) > 0
    error_message = "Give at least one SNS topic ARN when alarms is non-empty."
  }
  validation {
    condition     = alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "sns_topic_arns must be SNS topic ARNs."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "alarm 的 tag；`Name` 由 module 加上（metric filter 不支援 tag）。"
}
