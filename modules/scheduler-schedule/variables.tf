variable "kms_key_arn" {
  type        = string
  description = "加密排程資料（含 target 的 `input` 與 SageMaker pipeline 參數）用的客戶管理 KMS key ARN（symmetric），必填。key policy 要讓 `scheduler.amazonaws.com` 與 target 的 role 能用這把 key 的 `kms:Decrypt`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "group_name" {
  type        = string
  default     = null
  description = "schedule group 名稱，1–64 字元，限英數字、`_`、`-`、`.`，不能是 `default`。有值就建這個 group，所有排程放進去；`null` 就放 `default` group。"

  validation {
    condition     = var.group_name == null || (can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.group_name)) && var.group_name != "default")
    error_message = "group_name must be 1-64 chars of letters, digits, underscores, hyphens or dots, and must not be default."
  }
}

variable "schedules" {
  type = map(object({
    expression              = string
    timezone                = optional(string, "Asia/Taipei")
    state                   = optional(string, "ENABLED")
    flexible_window_minutes = optional(number)
    target = object({
      arn                           = string
      role_arn                      = string
      input                         = optional(string)
      sagemaker_pipeline_parameters = optional(map(string))
      dead_letter_arn               = optional(string)
      retry = optional(object({
        maximum_event_age_seconds = optional(number)
        maximum_retry_attempts    = optional(number)
      }))
    })
  }))
  default     = {}
  nullable    = false
  description = "排程，key 是排程名稱（1–64 字元，限英數字、`_`、`-`、`.`）。`expression` 是 `cron(...)`、`rate(...)` 或 `at(...)`；`timezone` 是 IANA 時區（預設 `Asia/Taipei`）；`state` 是 `ENABLED`（預設）或 `DISABLED`；`flexible_window_minutes` 1–1440，`null` 就是準時觸發（`OFF`）。`target.arn` 是 target 的 ARN；`target.role_arn` 是 Scheduler 呼叫 target 用的 role（必填，module 不建）；`input` 是送給 target 的內容；`sagemaker_pipeline_parameters` 是 pipeline 參數（名稱 → 值，最多 200 個），只能給 SageMaker pipeline target；`dead_letter_arn` 是 SQS queue ARN；`retry` 的 `maximum_event_age_seconds` 60–86400、`maximum_retry_attempts` 0–185。空的 map 就不建排程。"

  validation {
    condition     = alltrue([for name, _ in var.schedules : can(regex("^[a-zA-Z0-9_.-]{1,64}$", name))])
    error_message = "schedule names must be 1-64 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : can(regex("^(cron|rate|at)\\(.+\\)$", s.expression))])
    error_message = "schedule expression must start with cron(, rate( or at( and end with )."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : contains(["ENABLED", "DISABLED"], s.state)])
    error_message = "schedule state must be ENABLED or DISABLED."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : s.flexible_window_minutes == null || try(s.flexible_window_minutes >= 1 && s.flexible_window_minutes <= 1440 && s.flexible_window_minutes == floor(s.flexible_window_minutes), false)])
    error_message = "schedule flexible_window_minutes must be null (OFF) or a whole number between 1 and 1440."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", s.target.arn))])
    error_message = "schedule target arn must be an ARN (arn:<partition>:<service>:<region>:<account>:<resource>)."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : s.target.role_arn != null && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", s.target.role_arn))])
    error_message = "schedule target role_arn is required and must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition = alltrue([for _, s in var.schedules : s.target.sagemaker_pipeline_parameters == null || (
      can(regex("^arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:pipeline/.+$", s.target.arn)) && length(s.target.sagemaker_pipeline_parameters) <= 200
    )])
    error_message = "sagemaker_pipeline_parameters are only allowed for SageMaker pipeline targets and accept at most 200 entries."
  }

  validation {
    condition     = alltrue([for _, s in var.schedules : s.target.dead_letter_arn == null || can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:.+$", s.target.dead_letter_arn))])
    error_message = "schedule target dead_letter_arn must be an SQS queue ARN."
  }

  validation {
    condition = alltrue([for _, s in var.schedules : s.target.retry == null || (
      try(s.target.retry.maximum_event_age_seconds == null || (s.target.retry.maximum_event_age_seconds >= 60 && s.target.retry.maximum_event_age_seconds <= 86400 && s.target.retry.maximum_event_age_seconds == floor(s.target.retry.maximum_event_age_seconds)), false) &&
      try(s.target.retry.maximum_retry_attempts == null || (s.target.retry.maximum_retry_attempts >= 0 && s.target.retry.maximum_retry_attempts <= 185 && s.target.retry.maximum_retry_attempts == floor(s.target.retry.maximum_retry_attempts)), false)
    )])
    error_message = "schedule target retry maximum_event_age_seconds must be a whole number between 60 and 86400 and maximum_retry_attempts between 0 and 185."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "schedule group 的 tag；`Name` 由 module 加上。排程本身不支援 tag。"
}
