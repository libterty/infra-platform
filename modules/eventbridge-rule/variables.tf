variable "name" {
  type        = string
  description = "rule 名稱，1–64 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "event_bus_name" {
  type        = string
  default     = "default"
  nullable    = false
  description = "rule 掛的 event bus 名稱（預設 `default`）。module 不建 event bus；排程 rule 只能掛 `default`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,256}$", var.event_bus_name))
    error_message = "event_bus_name must be the name (not the ARN) of an event bus: 1-256 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "event_pattern" {
  type        = any
  default     = null
  description = "event pattern 物件（module 用 `jsonencode` 轉成 JSON），例如 `{ source = [\"aws.sagemaker\"], \"detail-type\" = [...] }`。與 `schedule_expression` 二擇一。"
}

variable "schedule_expression" {
  type        = string
  default     = null
  description = "排程運算式，`rate(...)` 或 `cron(...)`，只能用在 `default` bus。與 `event_pattern` 二擇一。新的排程建議用 `scheduler-schedule`（EventBridge Scheduler）。"

  validation {
    condition     = (var.event_pattern == null) != (var.schedule_expression == null)
    error_message = "Exactly one of event_pattern and schedule_expression must be set."
  }

  validation {
    condition     = var.schedule_expression == null || can(regex("^(rate|cron)\\(.+\\)$", var.schedule_expression))
    error_message = "schedule_expression must be a rate(...) or cron(...) expression."
  }

  validation {
    condition     = var.schedule_expression == null || var.event_bus_name == "default"
    error_message = "schedule_expression is only supported on the default event bus."
  }
}

variable "state" {
  type        = string
  default     = "ENABLED"
  nullable    = false
  description = "rule 的狀態：`ENABLED`（預設）、`DISABLED`，或 `ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS`（連 read-only 的 CloudTrail 管理事件也比對）。"

  validation {
    condition     = contains(["ENABLED", "DISABLED", "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"], var.state)
    error_message = "state must be ENABLED, DISABLED or ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS."
  }
}

variable "targets" {
  type = map(object({
    arn      = string
    role_arn = optional(string)
    input_transformer = optional(object({
      input_paths    = optional(map(string))
      input_template = string
    }))
    dead_letter_arn = optional(string)
    retry = optional(object({
      maximum_event_age_seconds = optional(number)
      maximum_retry_attempts    = optional(number)
    }))
    sqs_message_group_id = optional(string)
  }))
  description = "rule 的 target，1–5 個，key 是 target id（1–64 字元，限英數字、`_`、`-`、`.`）。`arn` 是 target 的 ARN；`role_arn` 是 EventBridge 呼叫 target 用的 role，SQS、SNS、Lambda 以外的 target 必填（這三種靠 resource policy 授權）；`input_transformer` 改寫送給 target 的內容；`dead_letter_arn` 是送不出去時放事件的 SQS queue ARN；`retry` 的 `maximum_event_age_seconds` 60–86400、`maximum_retry_attempts` 0–185；`sqs_message_group_id` 只給 FIFO queue target，而且 FIFO queue target 必填。"

  validation {
    condition     = length(var.targets) >= 1 && length(var.targets) <= 5
    error_message = "targets must have between 1 and 5 entries."
  }

  validation {
    condition     = alltrue([for id, _ in var.targets : can(regex("^[a-zA-Z0-9_.-]{1,64}$", id))])
    error_message = "target ids must be 1-64 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, t in var.targets : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", t.arn))])
    error_message = "target arn must be an ARN (arn:<partition>:<service>:<region>:<account>:<resource>)."
  }

  validation {
    condition     = alltrue([for _, t in var.targets : t.role_arn != null || contains(["sqs", "sns", "lambda"], try(split(":", t.arn)[2], ""))])
    error_message = "targets other than SQS, SNS and Lambda need a role_arn."
  }

  validation {
    condition     = alltrue([for _, t in var.targets : t.role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", t.role_arn))])
    error_message = "target role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for _, t in var.targets : t.dead_letter_arn == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", t.dead_letter_arn))])
    error_message = "target dead_letter_arn must be an SQS queue ARN."
  }

  validation {
    condition = alltrue([for _, t in var.targets : t.retry == null || (
      try(t.retry.maximum_event_age_seconds == null || (t.retry.maximum_event_age_seconds >= 60 && t.retry.maximum_event_age_seconds <= 86400 && t.retry.maximum_event_age_seconds == floor(t.retry.maximum_event_age_seconds)), false) &&
      try(t.retry.maximum_retry_attempts == null || (t.retry.maximum_retry_attempts >= 0 && t.retry.maximum_retry_attempts <= 185 && t.retry.maximum_retry_attempts == floor(t.retry.maximum_retry_attempts)), false)
    )])
    error_message = "target retry maximum_event_age_seconds must be a whole number between 60 and 86400 and maximum_retry_attempts between 0 and 185."
  }

  validation {
    condition = alltrue([for _, t in var.targets :
      (t.sqs_message_group_id != null) == (try(split(":", t.arn)[2], "") == "sqs" && endswith(t.arn, ".fifo"))
    ])
    error_message = "sqs_message_group_id is required for FIFO queue targets and only allowed for them."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "rule 的 tag；`Name` 由 module 加上。"
}
