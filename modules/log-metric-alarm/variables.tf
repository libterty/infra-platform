variable "name_prefix" {
  type        = string
  description = "Filter and alarm names are <name_prefix>-<key with _ replaced by ->."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,100}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits or hyphens."
  }
}

variable "log_group_name" {
  type        = string
  description = "Log group the metric filters read from."
}

variable "namespace" {
  type        = string
  description = "Custom metric namespace, e.g. Alpha/dev. Must not start with AWS/."
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
  description = "Alarm key => log pattern and alarm settings. Keys must be snake_case. description says what the alarm means and what to check first."
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

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions. Required."
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the alarms. Name is added by the module."
}
