variable "rules" {
  type = map(object({
    sql         = string
    description = optional(string)
    enabled     = optional(bool, true)
    actions = object({
      kinesis           = optional(list(object({ stream_name = string, role_arn = string, partition_key = optional(string) })), [])
      firehose          = optional(list(object({ delivery_stream_name = string, role_arn = string, separator = optional(string), batch_mode = optional(bool) })), [])
      s3                = optional(list(object({ bucket_name = string, key = string, role_arn = string })), [])
      sqs               = optional(list(object({ queue_url = string, role_arn = string, use_base64 = optional(bool, false) })), [])
      lambda            = optional(list(object({ function_arn = string })), [])
      dynamodbv2        = optional(list(object({ table_name = string, role_arn = string })), [])
      republish         = optional(list(object({ topic = string, role_arn = string, qos = optional(number, 0) })), [])
      cloudwatch_logs   = optional(list(object({ log_group_name = string, role_arn = string, batch_mode = optional(bool) })), [])
      cloudwatch_metric = optional(list(object({ metric_name = string, metric_namespace = string, metric_unit = string, metric_value = string, metric_timestamp = optional(string), role_arn = string })), [])
      sns               = optional(list(object({ target_arn = string, role_arn = string, message_format = optional(string, "RAW") })), [])
    })
  }))
  description = "IoT rule，rule 名稱（1–128 字元，限英數字與 `_`）→ 設定。`sql` 要以 `SELECT` 開頭，`sql_version` 固定 `2016-03-23`；`enabled` 預設 `true`。`actions` 只收 `kinesis`、`firehose`、`s3`、`sqs`、`lambda`、`dynamodbv2`、`republish`、`cloudwatch_logs`、`cloudwatch_metric`、`sns`，每種是 list，每條 rule 至少一個 action；其他種類不在型別裡，寫了會被 Terraform 忽略。`role_arn` 是讓 IoT 寫入目的地的 role，由呼叫端建立；Lambda 的 invoke permission 由 `lambda-function` 的 `permissions` 給。"

  validation {
    condition     = alltrue([for name in keys(var.rules) : can(regex("^[a-zA-Z0-9_]{1,128}$", name))])
    error_message = "rules keys (rule names) must be 1-128 chars of letters, digits or underscores; hyphens are not allowed."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : can(regex("^(?i)\\s*select\\s", r.sql))])
    error_message = "rules[*].sql must start with SELECT."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : length(flatten([for kind, list in r.actions : list])) >= 1])
    error_message = "Every rule must have at least one action."
  }

  validation {
    condition = alltrue([for arn in flatten([for r in values(var.rules) : [for kind, list in r.actions : [for a in list : try(a.role_arn, null)]]]) :
    arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", arn))])
    error_message = "Every action role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for a in flatten([for r in values(var.rules) : r.actions.lambda]) : can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]{1,64}(:[a-zA-Z0-9_$-]+)?$", a.function_arn))])
    error_message = "lambda.function_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }
}

variable "error_action" {
  type = object({
    kinesis           = optional(object({ stream_name = string, role_arn = string, partition_key = optional(string) }))
    firehose          = optional(object({ delivery_stream_name = string, role_arn = string, separator = optional(string), batch_mode = optional(bool) }))
    s3                = optional(object({ bucket_name = string, key = string, role_arn = string }))
    sqs               = optional(object({ queue_url = string, role_arn = string, use_base64 = optional(bool, false) }))
    lambda            = optional(object({ function_arn = string }))
    dynamodbv2        = optional(object({ table_name = string, role_arn = string }))
    republish         = optional(object({ topic = string, role_arn = string, qos = optional(number, 0) }))
    cloudwatch_logs   = optional(object({ log_group_name = string, role_arn = string, batch_mode = optional(bool) }))
    cloudwatch_metric = optional(object({ metric_name = string, metric_namespace = string, metric_unit = string, metric_value = string, metric_timestamp = optional(string), role_arn = string }))
    sns               = optional(object({ target_arn = string, role_arn = string, message_format = optional(string, "RAW") }))
  })
  nullable    = false
  description = "所有 rule 共用的 error action，必填，剛好給一種 action（種類同 `rules` 的 `actions`，但每種是單一物件）。action 失敗時 IoT 把錯誤送到這裡，常見是 SQS queue。"

  validation {
    condition     = length([for kind, a in var.error_action : kind if a != null]) == 1
    error_message = "error_action must set exactly one action."
  }

  validation {
    condition     = alltrue([for kind, a in var.error_action : a == null || try(a.role_arn, null) == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", try(a.role_arn, "")))])
    error_message = "error_action role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.error_action.lambda == null || can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]{1,64}(:[a-zA-Z0-9_$-]+)?$", try(var.error_action.lambda.function_arn, "")))
    error_message = "error_action.lambda.function_arn must be a Lambda function ARN (arn:<partition>:lambda:<region>:<account>:function:<name>[:<qualifier>])."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每條 rule 的 tag；`Name` 由 module 加上（rule 名稱）。"
}
