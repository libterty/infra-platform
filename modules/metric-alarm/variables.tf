variable "name_prefix" {
  type        = string
  description = "Alarm names are <name_prefix>-<key with _ replaced by ->."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,100}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits or hyphens."
  }
}

variable "alarms" {
  type = map(object({
    description         = string
    comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
    threshold           = number
    evaluation_periods  = optional(number, 1)
    datapoints_to_alarm = optional(number)
    treat_missing_data  = optional(string, "notBreaching")
    # Give exactly one of metric (a single metric) or queries (metric math).
    metric = optional(object({
      namespace   = string
      metric_name = string
      dimensions  = optional(map(string), {})
      statistic   = optional(string, "Average")
      period      = optional(number, 300)
    }))
    queries = optional(list(object({
      id          = string
      expression  = optional(string)
      label       = optional(string)
      return_data = optional(bool, false)
      metric = optional(object({
        namespace   = string
        metric_name = string
        dimensions  = optional(map(string), {})
        statistic   = optional(string, "Average")
        period      = optional(number, 300)
      }))
    })), [])
  }))
  description = "Alarm key => settings. Keys must be snake_case. description says what the alarm means and what to check first. Give either metric (one metric) or queries (metric math; exactly one query has return_data = true, and each query has either expression or metric)."

  validation {
    condition     = alltrue([for k, v in var.alarms : can(regex("^[a-z][a-z0-9_]*$", k)) && length(trimspace(v.description)) > 0])
    error_message = "Keys must be snake_case; description must not be empty."
  }
  validation {
    condition = alltrue([for v in values(var.alarms) :
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], v.comparison_operator) &&
      contains(["missing", "ignore", "breaching", "notBreaching"], v.treat_missing_data) &&
      v.evaluation_periods >= 1 &&
      (v.datapoints_to_alarm == null ? true : (v.datapoints_to_alarm >= 1 && v.datapoints_to_alarm <= v.evaluation_periods))
    ])
    error_message = "Use a supported comparison operator and treat_missing_data; evaluation_periods must be at least 1; datapoints_to_alarm must be between 1 and evaluation_periods."
  }
  validation {
    condition     = alltrue([for v in values(var.alarms) : (v.metric != null) != (length(v.queries) > 0)])
    error_message = "Each alarm needs exactly one of metric or queries."
  }
  validation {
    condition = alltrue([for v in values(var.alarms) : length(v.queries) == 0 || (
      length([for q in v.queries : q if q.return_data]) == 1 &&
      length(distinct([for q in v.queries : q.id])) == length(v.queries) &&
      alltrue([for q in v.queries : can(regex("^[a-z][A-Za-z0-9_]{0,254}$", q.id)) && ((q.expression != null) != (q.metric != null))])
    )])
    error_message = "In queries, ids must be unique and start with a lowercase letter, exactly one query must have return_data = true, and each query needs exactly one of expression or metric."
  }
  validation {
    condition = alltrue([
      for m in flatten([for v in values(var.alarms) : concat(v.metric == null ? [] : [v.metric], [for q in v.queries : q.metric if q.metric != null])]) :
      contains(["Sum", "Average", "Maximum", "Minimum", "SampleCount"], m.statistic) &&
      (m.period == 10 || m.period == 30 || (m.period >= 60 && m.period % 60 == 0))
    ])
    error_message = "Metric statistic must be Sum, Average, Maximum, Minimum or SampleCount; period must be 10, 30 or a multiple of 60."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "Topics for alarm_actions and ok_actions of every alarm. Required, at least one."
  validation {
    condition     = length(var.sns_topic_arns) > 0
    error_message = "Give at least one SNS topic ARN."
  }
  validation {
    condition     = alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "sns_topic_arns must be SNS topic ARNs."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the alarms. Name is added by the module."
}
