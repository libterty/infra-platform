variable "name" {
  type        = string
  description = "名稱前綴，alarm 名稱是 `<name>-<breaker key>-<signal>`，`signal` 為 `error-rate`、`healthy-hosts` 或 `custom`。2–60 字元，限小寫英數字與 `-`，以字母開頭。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,59}$", var.name))
    error_message = "name must be 2-60 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "load_balancer_type" {
  type        = string
  description = "`application`（ALB）或 `network`（NLB）。NLB 沒有 HTTP 狀態碼 metric，只有 healthy-hosts alarm 與選用的 `custom_metric` alarm。"
  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "load_balancer_type must be application or network."
  }
}

variable "load_balancer_arn_suffix" {
  type        = string
  description = "load balancer 的 `arn_suffix`，當作 metric 的 `LoadBalancer` dimension；ALB 是 `app/<name>/<id>`，NLB 是 `net/<name>/<id>`，要與 `load_balancer_type` 一致。"
  validation {
    condition     = can(regex("^${var.load_balancer_type == "network" ? "net" : "app"}/[A-Za-z0-9-]{1,32}/[0-9a-f]{16}$", var.load_balancer_arn_suffix))
    error_message = "load_balancer_arn_suffix must be app/<name>/<id> for an application load balancer and net/<name>/<id> for a network load balancer."
  }
}

variable "breakers" {
  type = map(object({
    listener_arn                   = optional(string)
    rule_arn                       = optional(string)
    stable_target_group_arn        = string
    canary_target_group_arn_suffix = string
    error_rate_percent             = optional(number)
    min_requests                   = optional(number)
    min_healthy_hosts              = optional(number, 1)
    period                         = optional(number, 60)
    evaluation_periods             = optional(number, 3)
    datapoints_to_alarm            = optional(number, 2)
    custom_metric = optional(object({
      namespace           = string
      metric_name         = string
      dimensions          = optional(map(string), {})
      statistic           = optional(string, "Average")
      threshold           = number
      comparison_operator = optional(string, "GreaterThanThreshold")
    }))
  }))
  description = "breaker key 對應一條「新系統出問題就把流量全部切回舊系統」的規則，至少一個。欄位見〈`breakers` 欄位〉。"

  validation {
    condition     = length(var.breakers) > 0 && alltrue([for k in keys(var.breakers) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Give at least one breaker; keys are 1-20 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
  validation {
    condition     = alltrue([for v in values(var.breakers) : (v.listener_arn != null) != (v.rule_arn != null)])
    error_message = "Each breaker needs exactly one of listener_arn or rule_arn."
  }
  validation {
    condition     = var.load_balancer_type != "network" || alltrue([for v in values(var.breakers) : v.rule_arn == null])
    error_message = "A network load balancer only supports listener_arn; rule_arn is rejected."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) : v.listener_arn == null ? true : (
      can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:listener/(app|net)/[A-Za-z0-9-]{1,32}/[0-9a-f]{16}/[0-9a-f]{16}$", v.listener_arn)) &&
      strcontains(v.listener_arn, ":listener/${var.load_balancer_arn_suffix}/")
    )])
    error_message = "listener_arn must be a listener ARN of the load balancer given by load_balancer_arn_suffix."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) : v.rule_arn == null ? true : (
      can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:listener-rule/(app|net)/[A-Za-z0-9-]{1,32}/[0-9a-f]{16}/[0-9a-f]{16}/[0-9a-f]{16}$", v.rule_arn)) &&
      strcontains(v.rule_arn, ":listener-rule/${var.load_balancer_arn_suffix}/")
    )])
    error_message = "rule_arn must be a listener rule ARN of the load balancer given by load_balancer_arn_suffix."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) :
      can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]{1,32}/[0-9a-f]{16}$", v.stable_target_group_arn)) &&
      can(regex("^targetgroup/[A-Za-z0-9-]{1,32}/[0-9a-f]{16}$", v.canary_target_group_arn_suffix))
    ])
    error_message = "stable_target_group_arn must be a target group ARN; canary_target_group_arn_suffix must be targetgroup/<name>/<id> (the arn_suffix attribute, not the ARN)."
  }
  validation {
    condition     = alltrue([for v in values(var.breakers) : !endswith(v.stable_target_group_arn, ":${v.canary_target_group_arn_suffix}")])
    error_message = "stable_target_group_arn and canary_target_group_arn_suffix must be different target groups."
  }
  validation {
    condition     = var.load_balancer_type != "network" || alltrue([for v in values(var.breakers) : v.error_rate_percent == null && v.min_requests == null])
    error_message = "A network load balancer has no HTTP status metrics: error_rate_percent and min_requests are rejected. Use min_healthy_hosts or custom_metric."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) :
      (v.error_rate_percent == null ? true : (v.error_rate_percent > 0 && v.error_rate_percent <= 100)) &&
      (v.min_requests == null ? true : (v.min_requests >= 1 && v.min_requests == floor(v.min_requests))) &&
      v.min_healthy_hosts >= 1 && v.min_healthy_hosts == floor(v.min_healthy_hosts)
    ])
    error_message = "error_rate_percent must be above 0 and at most 100; min_requests and min_healthy_hosts must be whole numbers of at least 1."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) :
      v.period >= 60 && v.period % 60 == 0 &&
      v.evaluation_periods >= 1 && v.evaluation_periods == floor(v.evaluation_periods) &&
      v.datapoints_to_alarm >= 1 && v.datapoints_to_alarm <= v.evaluation_periods && v.datapoints_to_alarm == floor(v.datapoints_to_alarm) &&
      v.period * v.evaluation_periods <= 86400
    ])
    error_message = "period must be a multiple of 60; evaluation_periods at least 1; datapoints_to_alarm between 1 and evaluation_periods; period * evaluation_periods at most 86400 seconds (CloudWatch limit)."
  }
  validation {
    condition = alltrue([for v in values(var.breakers) : v.custom_metric == null ? true : (
      length(trimspace(v.custom_metric.namespace)) > 0 &&
      length(trimspace(v.custom_metric.metric_name)) > 0 &&
      contains(["Sum", "Average", "Maximum", "Minimum", "SampleCount"], v.custom_metric.statistic) &&
      contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], v.custom_metric.comparison_operator)
    )])
    error_message = "custom_metric needs a namespace and metric_name, a statistic of Sum, Average, Maximum, Minimum or SampleCount, and a supported comparison_operator."
  }
}

variable "lambda_function_arn" {
  type        = string
  description = "斷路器 Lambda function 的 ARN，不可帶 version 或 alias：`lambda_permissions` 的呼叫權限授予在 function 本身。"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}$", var.lambda_function_arn))
    error_message = "lambda_function_arn must be a Lambda function ARN without a version or alias qualifier."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "所有 alarm 的 `alarm_actions` 與 `ok_actions` 用的 SNS topic ARN，至少一個；斷路器觸發與 alarm 恢復時都會通知。"
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
  description = "alarm 的 tag；`Name` 由 module 加上。"
}
