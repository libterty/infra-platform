variable "name" {
  type        = string
  description = "部署名稱，1–256 字元，顯示在 Greengrass console 與 API，也用在 `Name` tag。"

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 256
    error_message = "name must be 1-256 characters."
  }
}

variable "target_arn" {
  type        = string
  description = "部署對象：一個 thing group（`arn:aws:iot:<region>:<account>:thinggroup/<name>`）或一台 core device 的 thing（`.../thing/<name>`）。每個 target 只有一個部署，新部署會取代舊的。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iot:[a-z0-9-]+:[0-9]{12}:(thinggroup|thing)/[A-Za-z0-9:_-]{1,128}$", var.target_arn))
    error_message = "target_arn must be an IoT thing group ARN (...:thinggroup/<name>) or thing ARN (...:thing/<name>)."
  }
}

variable "components" {
  type        = any
  nullable    = false
  description = "要部署的元件，key 是元件名稱（含 `aws.greengrass.Nucleus` 與公開元件），value 是物件：`version`（必填，semver）、`merge`（選填，要合併進元件設定的物件，module 會 `jsonencode`）、`reset`（選填，要重設成預設值的 JSON pointer 清單）、`run_with`（選填，`{ posix_user = \"user:group\" }`）。至少一個元件；不在這裡的元件會從裝置上解除安裝。型別是 `any`，因為每個元件的 `merge` 形狀不同。"

  validation {
    condition     = can(keys(var.components)) && length(keys(var.components)) > 0
    error_message = "components must be a map with at least one component."
  }

  validation {
    condition     = alltrue([for k in try(keys(var.components), []) : can(regex("^[A-Za-z0-9._-]{1,128}$", k))])
    error_message = "Component names must be 1-128 chars of letters, digits, dots, underscores and hyphens."
  }

  validation {
    condition = alltrue([
      for v in try(values(var.components), []) :
      can(keys(v)) && length(setsubtract(keys(v), ["version", "merge", "reset", "run_with"])) == 0
    ])
    error_message = "Each component accepts only version, merge, reset and run_with."
  }

  validation {
    condition = alltrue([
      for v in try(values(var.components), []) :
      can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$", v.version))
    ])
    error_message = "Each component needs a version that is a semantic version (major.minor.patch)."
  }

  validation {
    condition = alltrue([
      for v in try(values(var.components), []) :
      try(v.merge, null) == null || can(keys(v.merge))
    ])
    error_message = "merge must be an object; the module JSON-encodes it."
  }

  validation {
    condition = alltrue([
      for v in try(values(var.components), []) :
      try(v.reset, null) == null || can(tolist([for r in v.reset : tostring(r)]))
    ])
    error_message = "reset must be a list of JSON pointers."
  }

  validation {
    condition = alltrue([
      for v in try(values(var.components), []) :
      try(v.run_with, null) == null || (
        can(keys(v.run_with)) &&
        length(setsubtract(try(keys(v.run_with), []), ["posix_user"])) == 0 &&
        can(regex("^[a-z_][a-z0-9_-]{0,31}(:[a-z_][a-z0-9_-]{0,31})?$", v.run_with.posix_user))
      )
    ])
    error_message = "run_with accepts only posix_user, formatted as user or user:group."
  }
}

variable "failure_handling" {
  type        = string
  default     = "ROLLBACK"
  nullable    = false
  description = "裝置部署失敗時的處理：`ROLLBACK`（預設，回到上一版的元件與設定）或 `DO_NOTHING`。"

  validation {
    condition     = contains(["ROLLBACK", "DO_NOTHING"], var.failure_handling)
    error_message = "failure_handling must be ROLLBACK or DO_NOTHING."
  }
}

variable "component_update" {
  type = object({
    action          = optional(string, "NOTIFY_COMPONENTS")
    timeout_seconds = optional(number, 60)
  })
  default     = {}
  nullable    = false
  description = "元件更新政策：`action` 是 `NOTIFY_COMPONENTS`（預設，先通知元件，讓元件可以延後更新）或 `SKIP_NOTIFY_COMPONENTS`；`timeout_seconds` 是等元件回應的秒數（預設 60）。"

  validation {
    condition     = contains(["NOTIFY_COMPONENTS", "SKIP_NOTIFY_COMPONENTS"], var.component_update.action)
    error_message = "component_update.action must be NOTIFY_COMPONENTS or SKIP_NOTIFY_COMPONENTS."
  }

  validation {
    condition     = var.component_update.timeout_seconds >= 1 && var.component_update.timeout_seconds == floor(var.component_update.timeout_seconds)
    error_message = "component_update.timeout_seconds must be a whole number >= 1."
  }
}

variable "configuration_validation_timeout_seconds" {
  type        = number
  default     = 30
  nullable    = false
  description = "元件驗證新設定的等待秒數（預設 30）。"

  validation {
    condition     = var.configuration_validation_timeout_seconds >= 1 && var.configuration_validation_timeout_seconds == floor(var.configuration_validation_timeout_seconds)
    error_message = "configuration_validation_timeout_seconds must be a whole number >= 1."
  }
}

variable "rollout" {
  type = object({
    maximum_per_minute = optional(number)
    exponential = optional(object({
      base_rate_per_minute       = number
      increment_factor           = number
      number_of_succeeded_things = number
    }))
  })
  nullable    = false
  description = "發布速度，必填，`maximum_per_minute`（每分鐘最多通知幾台，1–1000）與 `exponential` 擇一。`exponential` 的欄位：`base_rate_per_minute`（1–1000）、`increment_factor`（1.1–5）、`number_of_succeeded_things`（成功幾台後加速，至少 1）。"

  validation {
    condition     = (var.rollout.maximum_per_minute == null) != (var.rollout.exponential == null)
    error_message = "rollout needs exactly one of maximum_per_minute and exponential."
  }

  validation {
    condition     = var.rollout.maximum_per_minute == null || try(var.rollout.maximum_per_minute >= 1 && var.rollout.maximum_per_minute <= 1000 && var.rollout.maximum_per_minute == floor(var.rollout.maximum_per_minute), false)
    error_message = "rollout.maximum_per_minute must be a whole number between 1 and 1000."
  }

  validation {
    condition = var.rollout.exponential == null || try(
      var.rollout.exponential.base_rate_per_minute >= 1 && var.rollout.exponential.base_rate_per_minute <= 1000 &&
      var.rollout.exponential.increment_factor >= 1.1 && var.rollout.exponential.increment_factor <= 5 &&
      var.rollout.exponential.number_of_succeeded_things >= 1,
      false
    )
    error_message = "rollout.exponential needs base_rate_per_minute 1-1000, increment_factor 1.1-5 and number_of_succeeded_things >= 1."
  }
}

variable "abort" {
  type = list(object({
    failure_type                  = string
    threshold_percentage          = number
    min_number_of_executed_things = number
  }))
  nullable    = false
  description = "中止條件，必填，至少一條；符合任一條就取消還沒收到的裝置（`action` 固定 `CANCEL`）。欄位：`failure_type`（`FAILED`、`REJECTED`、`TIMED_OUT`、`ALL`）、`threshold_percentage`（大於 0、最多 100）、`min_number_of_executed_things`（至少執行幾台才開始判斷，至少 1）。"

  validation {
    condition     = length(var.abort) > 0
    error_message = "abort needs at least one criterion."
  }

  validation {
    condition     = alltrue([for a in var.abort : contains(["FAILED", "REJECTED", "TIMED_OUT", "ALL"], a.failure_type)])
    error_message = "abort failure_type must be FAILED, REJECTED, TIMED_OUT or ALL."
  }

  validation {
    condition     = alltrue([for a in var.abort : a.threshold_percentage > 0 && a.threshold_percentage <= 100])
    error_message = "abort threshold_percentage must be greater than 0 and at most 100."
  }

  validation {
    condition     = alltrue([for a in var.abort : a.min_number_of_executed_things >= 1 && a.min_number_of_executed_things == floor(a.min_number_of_executed_things)])
    error_message = "abort min_number_of_executed_things must be a whole number >= 1."
  }
}

variable "in_progress_timeout_minutes" {
  type        = number
  default     = null
  description = "每台裝置執行部署的時間上限（分鐘，1–10080）；超過就標成 `TIMED_OUT`。`null` 不設上限。"

  validation {
    condition     = var.in_progress_timeout_minutes == null || try(var.in_progress_timeout_minutes >= 1 && var.in_progress_timeout_minutes <= 10080 && var.in_progress_timeout_minutes == floor(var.in_progress_timeout_minutes), false)
    error_message = "in_progress_timeout_minutes must be a whole number between 1 and 10080."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "部署的 tag；`Name`（部署名稱）由 module 加上。"
}
