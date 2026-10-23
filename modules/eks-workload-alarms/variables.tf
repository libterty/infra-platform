variable "name" {
  type        = string
  description = "告警名稱前綴，通常用工作負載名稱；告警命名為 `<name>-<key>`。小寫字母開頭，限小寫英數字與連字號，2–201 字元。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,200}$", var.name))
    error_message = "name must be lowercase letters, digits or hyphens."
  }
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster 名稱，當作 Container Insights 的 `ClusterName` 維度。不可為空。"
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "namespace" {
  type        = string
  description = "工作負載所在的 Kubernetes namespace（`Namespace` 維度）。須符合 DNS label：小寫英數字與連字號，最多 63 字元。"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a Kubernetes DNS label: lowercase letters, digits or hyphens, up to 63 characters."
  }
}

variable "workload_name" {
  type        = string
  description = "Deployment 名稱；Container Insights 把它放在 `PodName` 維度。不可為空。"
  validation {
    condition     = length(var.workload_name) > 0
    error_message = "workload_name must not be empty."
  }
}

variable "container_name" {
  type        = string
  description = "pod 裡的容器名稱，當作 OOM 告警的 `ContainerName` 維度。不可為空。"
  validation {
    condition     = length(var.container_name) > 0
    error_message = "container_name must not be empty."
  }
}

variable "sns_topic_arns" {
  type        = list(string)
  description = "接收告警與恢復通知（`alarm_actions`、`ok_actions`）的 SNS topic ARN，至少一個：沒人收的告警等於沒有告警。"
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
  description = "ALB 的 CloudWatch 維度；給了才建 ALB target 告警，`null` 時不建。欄位：`alb_arn_suffix`（`app/<name>/<id>`）、`target_group_arn_suffix`（`targetgroup/<name>/<id>`），都要用 ARN 後綴，不是完整 ARN。"
  validation {
    condition     = var.load_balancer == null ? true : (startswith(var.load_balancer.alb_arn_suffix, "app/") && startswith(var.load_balancer.target_group_arn_suffix, "targetgroup/"))
    error_message = "Use ARN suffixes: app/... and targetgroup/... (CloudWatch dimension format)."
  }
}

variable "restart_threshold" {
  type        = number
  default     = 0
  description = "5 分鐘內容器重啟次數超過這個值，`restarts` 告警就觸發。不可為負。"
  validation {
    condition     = var.restart_threshold >= 0
    error_message = "restart_threshold must be 0 or more."
  }
}

variable "alarm_config" {
  type = object({
    alb = optional(object({
      target_5xx_ratio_threshold = optional(number, 0.01)
      latency_p95_threshold_ms   = optional(number, 800)
      healthy_host_min           = optional(number, 1)
    }), {})
  })
  default     = {}
  description = "ALB 告警門檻覆寫，每個欄位都有預設。`alb` 欄位：`target_5xx_ratio_threshold`（預設 `0.01`，不可為負）、`latency_p95_threshold_ms`（預設 `800`，須大於 0）、`healthy_host_min`（預設 `1`，不可為負）。"
  validation {
    condition     = var.alarm_config.alb.target_5xx_ratio_threshold >= 0 && var.alarm_config.alb.latency_p95_threshold_ms > 0 && var.alarm_config.alb.healthy_host_min >= 0
    error_message = "ALB thresholds: ratio and healthy_host_min must be 0 or more, latency_p95_threshold_ms must be above 0."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個告警的 tag。"
}
