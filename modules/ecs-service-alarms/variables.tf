variable "name" {
  type        = string
  description = "告警名稱前綴，通常就是 service 名稱；告警名稱為 `<name>-<key>`。限小寫英數字與連字號，字母開頭，2–201 字元。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,200}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens."
  }
}

variable "cluster_name" {
  type        = string
  description = "ECS cluster 名稱（CloudWatch `ClusterName` 維度）。"
}

variable "service_name" {
  type        = string
  description = "ECS service 名稱（CloudWatch `ServiceName` 維度）。"
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "接收告警（`alarm_actions`）與恢復通知（`ok_actions`）的 SNS topic ARN，至少一個：沒人收的告警不算告警。"
  validation {
    condition     = length(var.sns_topic_arns) > 0 && alltrue([for a in var.sns_topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", a))])
    error_message = "Give at least one SNS topic ARN."
  }
}

variable "load_balancer" {
  type = object({
    alb_arn_suffix          = string # app/<name>/<id>
    target_group_arn_suffix = string # targetgroup/<name>/<id>
  })
  default     = null
  description = "ALB 的 CloudWatch 維度；`null` 時不建 ALB target 告警。欄位：`alb_arn_suffix`（`app/<name>/<id>`）、`target_group_arn_suffix`（`targetgroup/<name>/<id>`），都要用 suffix，不是完整 ARN。"
  validation {
    condition     = var.load_balancer == null ? true : (startswith(var.load_balancer.alb_arn_suffix, "app/") && startswith(var.load_balancer.target_group_arn_suffix, "targetgroup/"))
    error_message = "Use ARN suffixes: app/... and targetgroup/... (CloudWatch dimension format)."
  }
}

variable "max_capacity" {
  type        = number
  default     = null
  description = "autoscaling 的最大 task 數；給了數字才建 `at_max_capacity` 告警。"
}

variable "alarm_config" {
  type = object({
    ecs = optional(object({
      cpu_threshold    = optional(number, 80)
      memory_threshold = optional(number, 80)
    }), {})
    container = optional(object({
      cpu_throttling_threshold  = optional(number, 0.9)
      memory_pressure_threshold = optional(number, 0.85)
    }), {})
    alb = optional(object({
      target_5xx_ratio_threshold = optional(number, 0.01)
      target_4xx_ratio_threshold = optional(number, 0.05)
      latency_p95_threshold_ms   = optional(number, 800)
      healthy_host_min           = optional(number, 1)
    }), {})
  })
  default     = {}
  description = "告警門檻。欄位：`ecs`（`cpu_threshold`、`memory_threshold`，預設皆 `80`）、`container`（`cpu_throttling_threshold` 預設 `0.9`、`memory_pressure_threshold` 預設 `0.85`）、`alb`（`target_5xx_ratio_threshold` 預設 `0.01`、`target_4xx_ratio_threshold` 預設 `0.05`、`latency_p95_threshold_ms` 預設 `800`、`healthy_host_min` 預設 `1`）。各告警見〈告警清單〉。"
}

variable "dashboard_name" {
  type        = string
  default     = null
  description = "dashboard 名稱；`null` 時不建 dashboard。"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "告警的 tag。"
}
