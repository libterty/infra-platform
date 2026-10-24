variable "name" {
  type        = string
  description = "這個 module 的名稱，1–255 字元，限英數字、`_`、`-`、`.`。用作 security configuration 的名稱，也是 job log group 的路徑（`/aws-glue/jobs/<name>/<job>`）。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,255}$", var.name))
    error_message = "name must be 1-255 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "加密用的客戶管理 KMS key ARN（symmetric），必填。用在 security configuration（job 寫 S3 的資料、CloudWatch log、job bookmark）與 module 自己建的 log group。key policy 或 job、crawler 的 role 要有這把 key 的 `kms:Decrypt`、`kms:GenerateDataKey`、`kms:Encrypt`。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  nullable    = false
  description = "module 自己建的 job log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 30）。Glue 自己建的 log group（`/aws-glue/jobs/output`、`/aws-glue/crawlers` 等）不受這個設定影響。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "crawlers" {
  type = map(object({
    role_arn      = string
    database_name = string
    s3_paths      = list(string)
    schedule      = optional(string)
    table_prefix  = optional(string)
    description   = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "crawler，key 是 crawler 名稱（1–255 字元，限英數字、`_`、`-`、`.`）。`role_arn` 是 crawler 用的 IAM role ARN（module 不建 role）；`database_name` 是寫入的 Glue database；`s3_paths` 是要掃的 `s3://` 路徑（至少一個）；`schedule` 是 `cron(...)` 運算式，沒給就只能手動或由 trigger 啟動；`table_prefix`、`description` 選填。每次執行最低計費 10 分鐘。crawler 一律掛 module 的 security configuration。"

  validation {
    condition     = alltrue([for name, _ in var.crawlers : can(regex("^[a-zA-Z0-9_.-]{1,255}$", name))])
    error_message = "crawler names must be 1-255 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, c in var.crawlers : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", c.role_arn))])
    error_message = "crawler role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for _, c in var.crawlers : length(c.s3_paths) >= 1 && alltrue([for p in c.s3_paths : can(regex("^s3://[^/]+", p))])])
    error_message = "crawler s3_paths must have at least one entry and every entry must start with s3://<bucket>."
  }

  validation {
    condition     = alltrue([for _, c in var.crawlers : c.schedule == null || can(regex("^cron\\(.+\\)$", c.schedule))])
    error_message = "crawler schedule must be a cron(...) expression."
  }
}

variable "jobs" {
  type = map(object({
    role_arn            = string
    script_location     = string
    glue_version        = optional(string, "5.1")
    worker_type         = optional(string, "G.1X")
    number_of_workers   = optional(number, 2)
    execution_class     = optional(string, "STANDARD")
    timeout             = optional(number, 60)
    max_retries         = optional(number, 0)
    max_concurrent_runs = optional(number, 1)
    default_arguments   = optional(map(string), {})
    description         = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Spark ETL job（`glueetl`），key 是 job 名稱（1–255 字元，限英數字、`_`、`-`、`.`）。`role_arn` 是 job 用的 IAM role ARN（module 不建 role）；`script_location` 是 `s3://` 的腳本路徑（module 不上傳腳本）；`glue_version` 可選 `3.0`、`4.0`、`5.0`、`5.1`（預設）、`6.0`；`worker_type` 可選 `G.1X`（預設）、`G.2X`、`G.4X`、`G.8X`；`number_of_workers` 至少 2；`execution_class` 是 `STANDARD`（預設）或 `FLEX`（只能搭 `G.1X`、`G.2X`）；`timeout` 是分鐘，1–2880（預設 60）；`default_arguments` 例如 `--job-bookmark-option`，module 會另外加上 continuous logging 的兩個參數且不可覆蓋。job 一律掛 module 的 security configuration。"

  validation {
    condition     = alltrue([for name, _ in var.jobs : can(regex("^[a-zA-Z0-9_.-]{1,255}$", name))])
    error_message = "job names must be 1-255 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", j.role_arn))])
    error_message = "job role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : can(regex("^s3://[^/]+/.+", j.script_location))])
    error_message = "job script_location must be an s3://<bucket>/<key> path."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : contains(["3.0", "4.0", "5.0", "5.1", "6.0"], j.glue_version)])
    error_message = "job glue_version must be one of 3.0, 4.0, 5.0, 5.1, 6.0."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : contains(["G.1X", "G.2X", "G.4X", "G.8X"], j.worker_type)])
    error_message = "job worker_type must be one of G.1X, G.2X, G.4X, G.8X."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : contains(["STANDARD", "FLEX"], j.execution_class)])
    error_message = "job execution_class must be STANDARD or FLEX."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : j.execution_class != "FLEX" || contains(["G.1X", "G.2X"], j.worker_type)])
    error_message = "job execution_class FLEX only supports the G.1X and G.2X worker types."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : j.number_of_workers >= 2 && j.number_of_workers == floor(j.number_of_workers)])
    error_message = "job number_of_workers must be a whole number >= 2 (Spark jobs need at least 2 DPUs)."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : j.timeout >= 1 && j.timeout <= 2880 && j.timeout == floor(j.timeout)])
    error_message = "job timeout must be a whole number of minutes between 1 and 2880."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : j.max_retries >= 0 && j.max_retries == floor(j.max_retries)])
    error_message = "job max_retries must be a whole number >= 0."
  }

  validation {
    condition     = alltrue([for _, j in var.jobs : j.max_concurrent_runs >= 1 && j.max_concurrent_runs == floor(j.max_concurrent_runs)])
    error_message = "job max_concurrent_runs must be a whole number >= 1."
  }
}

variable "workflow" {
  type = object({
    name                = string
    description         = optional(string)
    max_concurrent_runs = optional(number)
  })
  default     = null
  description = "Glue workflow；`null` 不建。`name` 限英數字、`_`、`-`，1–255 字元；`event_trigger` 與 `triggers` 的 `workflow = true` 都要有它。"

  validation {
    condition     = var.workflow == null || can(regex("^[a-zA-Z0-9_-]{1,255}$", var.workflow.name))
    error_message = "workflow name must be 1-255 chars of letters, digits, underscores or hyphens."
  }
}

variable "triggers" {
  type = map(object({
    type     = string
    schedule = optional(string)
    enabled  = optional(bool, true)
    workflow = optional(bool, false)
    predicate = optional(object({
      logical = optional(string, "AND")
      conditions = list(object({
        job     = optional(string)
        crawler = optional(string)
        state   = string
      }))
    }))
    actions = list(object({
      job       = optional(string)
      crawler   = optional(string)
      arguments = optional(map(string), {})
    }))
    description = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "trigger，key 是 trigger 名稱。`type` 是 `SCHEDULED`（要 `schedule` 的 `cron(...)`，不能有 `predicate`）或 `CONDITIONAL`（要 `predicate`，不能有 `schedule`）；`actions` 至少一個，每個恰好指向這個 module 的一個 `job` 或 `crawler`；`predicate.conditions` 的 `state` 對 job 是 `SUCCEEDED`、`STOPPED`、`TIMEOUT`、`FAILED`，對 crawler 是 `RUNNING`、`SUCCEEDED`、`CANCELLED`、`FAILED`；`workflow = true` 把 trigger 放進 `workflow`（要先給 `workflow`）；`workflow = true` 的 `SCHEDULED` 是 workflow 的起始 trigger，最多一個，有 `event_trigger` 時不能有。EVENT trigger 不在這裡，用 `event_trigger`。"

  validation {
    condition     = alltrue([for name, _ in var.triggers : can(regex("^[a-zA-Z0-9_.-]{1,255}$", name))])
    error_message = "trigger names must be 1-255 chars of letters, digits, underscores, hyphens or dots."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : contains(["SCHEDULED", "CONDITIONAL"], t.type)])
    error_message = "trigger type must be SCHEDULED or CONDITIONAL (use event_trigger for EventBridge-driven triggers)."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : t.type != "SCHEDULED" || (t.predicate == null && can(regex("^cron\\(.+\\)$", t.schedule)))])
    error_message = "a SCHEDULED trigger needs a cron(...) schedule and must not have a predicate."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : t.type != "CONDITIONAL" || (t.schedule == null && t.predicate != null)])
    error_message = "a CONDITIONAL trigger needs a predicate and must not have a schedule."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : t.predicate == null || contains(["AND", "ANY"], t.predicate.logical)])
    error_message = "predicate logical must be AND or ANY."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : t.predicate == null || length(t.predicate.conditions) >= 1])
    error_message = "a predicate needs at least one condition."
  }

  validation {
    condition = alltrue(flatten([for _, t in var.triggers : [
      for c in(t.predicate == null ? [] : t.predicate.conditions) :
      (c.job != null) != (c.crawler != null)
    ]]))
    error_message = "every predicate condition must name exactly one of job or crawler."
  }

  validation {
    condition = alltrue(flatten([for _, t in var.triggers : [
      for c in(t.predicate == null ? [] : t.predicate.conditions) :
      c.job != null ? contains(["SUCCEEDED", "STOPPED", "TIMEOUT", "FAILED"], c.state) : (c.crawler == null || contains(["RUNNING", "SUCCEEDED", "CANCELLED", "FAILED"], c.state))
    ]]))
    error_message = "a job condition state must be SUCCEEDED, STOPPED, TIMEOUT or FAILED; a crawler condition state must be RUNNING, SUCCEEDED, CANCELLED or FAILED."
  }

  validation {
    condition = alltrue(flatten([for _, t in var.triggers : [
      for c in(t.predicate == null ? [] : t.predicate.conditions) :
      c.job != null ? contains(keys(var.jobs), c.job) : (c.crawler == null || contains(keys(var.crawlers), c.crawler))
    ]]))
    error_message = "every predicate condition must point to a job or crawler defined in this module."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : length(t.actions) >= 1])
    error_message = "a trigger needs at least one action."
  }

  validation {
    condition     = alltrue(flatten([for _, t in var.triggers : [for a in t.actions : (a.job != null) != (a.crawler != null)]]))
    error_message = "every trigger action must name exactly one of job or crawler."
  }

  validation {
    condition = alltrue(flatten([for _, t in var.triggers : [
      for a in t.actions :
      a.job != null ? contains(keys(var.jobs), a.job) : (a.crawler == null || contains(keys(var.crawlers), a.crawler))
    ]]))
    error_message = "every trigger action must point to a job or crawler defined in this module."
  }

  validation {
    condition     = alltrue([for _, t in var.triggers : !t.workflow || var.workflow != null])
    error_message = "workflow = true needs the workflow input to be set."
  }

  # A Glue workflow has a single start trigger; CONDITIONAL triggers are the ones that chain after it.
  validation {
    condition     = length([for _, t in var.triggers : t if t.workflow && t.type == "SCHEDULED"]) <= 1
    error_message = "A workflow has a single start trigger: at most one SCHEDULED trigger may set workflow = true."
  }
}

variable "event_trigger" {
  type = object({
    bucket_name = string
    key_prefix  = string
    role_arn    = string
    actions = list(object({
      job       = optional(string)
      crawler   = optional(string)
      arguments = optional(map(string), {})
    }))
    batch_size           = number
    batch_window_seconds = optional(number, 900)
  })
  default     = null
  description = "S3 事件觸發 `workflow`；`null` 不建。module 會建 `type = \"EVENT\"` 的 trigger 當 workflow 的起始 trigger（名稱 `<workflow>-s3-event`），以及 default bus 上同名的 EventBridge rule 與指向 workflow 的 target。rule 只比對 `bucket_name` 這個 bucket、`key_prefix`（不可為空、不可以 `/` 開頭）開頭的 `Object Created` 事件；bucket 要先開 EventBridge 通知（`s3-bucket` 的 `eventbridge = true`）。`role_arn` 是 EventBridge assume 的 IAM role ARN（module 不建 role，權限是對這個 workflow 的 `glue:notifyEvent`）。`batch_size` 1–100，`batch_window_seconds` 1–900（預設 900）：事件數或視窗（從第一個事件起算）先到先觸發。`actions` 的規則同 `triggers`。要有 `workflow`，且 workflow 名稱最長 55 字元（rule 名稱上限 64）。"

  validation {
    condition     = var.event_trigger == null || var.workflow != null
    error_message = "event_trigger needs the workflow input to be set (the EVENT trigger is the start trigger of the workflow)."
  }

  validation {
    condition     = var.event_trigger == null || length([for _, t in var.triggers : t if t.workflow && t.type == "SCHEDULED"]) == 0
    error_message = "event_trigger is the start trigger of the workflow, so no SCHEDULED trigger may set workflow = true."
  }

  validation {
    condition     = var.event_trigger == null || var.workflow == null || length(var.workflow.name) <= 55
    error_message = "with event_trigger the workflow name must be at most 55 characters, because the EventBridge rule is named <workflow>-s3-event and rule names are limited to 64."
  }

  validation {
    condition     = var.event_trigger == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.event_trigger.bucket_name))
    error_message = "event_trigger bucket_name must be a valid S3 bucket name (3-63 chars of lowercase letters, digits, dots and hyphens)."
  }

  validation {
    condition     = var.event_trigger == null || can(regex("^[^/].*$", var.event_trigger.key_prefix))
    error_message = "event_trigger key_prefix must not be empty and must not start with / (an empty prefix would match every object in the bucket)."
  }

  validation {
    condition     = var.event_trigger == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.event_trigger.role_arn))
    error_message = "event_trigger role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }

  validation {
    condition     = var.event_trigger == null || (var.event_trigger.batch_size >= 1 && var.event_trigger.batch_size <= 100 && var.event_trigger.batch_size == floor(var.event_trigger.batch_size))
    error_message = "event_trigger batch_size must be a whole number between 1 and 100."
  }

  validation {
    condition     = var.event_trigger == null || (var.event_trigger.batch_window_seconds >= 1 && var.event_trigger.batch_window_seconds <= 900 && var.event_trigger.batch_window_seconds == floor(var.event_trigger.batch_window_seconds))
    error_message = "event_trigger batch_window_seconds must be a whole number between 1 and 900."
  }

  validation {
    condition     = var.event_trigger == null || length(var.event_trigger.actions) >= 1
    error_message = "event_trigger needs at least one action."
  }

  validation {
    condition = var.event_trigger == null || alltrue([
      for a in var.event_trigger.actions :
      (a.job != null) != (a.crawler != null) && (a.job != null ? contains(keys(var.jobs), a.job) : contains(keys(var.crawlers), a.crawler))
    ])
    error_message = "every event_trigger action must name exactly one of job or crawler, defined in this module."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個 resource 的 tag；`Name` 由 module 加上。"
}
