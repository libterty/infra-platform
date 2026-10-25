variable "name" {
  type        = string
  description = "endpoint 名稱，1–36 字元，限英數字與 `-`，開頭結尾是英數字。endpoint configuration 用 `<name>-` 當 `name_prefix`，後面接 26 字元的亂數，總長不能超過 63，所以上限是 36。"

  validation {
    condition     = length(var.name) <= 36 && can(regex("^[a-zA-Z0-9](-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be 1-36 chars of letters, digits and hyphens, starting and ending with a letter or digit (the endpoint configuration name prefix adds 27 chars)."
  }
}

variable "model_package_arn" {
  type        = string
  description = "要部署的 model package 版本 ARN（`arn:<partition>:sagemaker:<region>:<account>:model-package/<group>/<version>`），要是核准過的版本。module 只從 model package 建 model，不收任意 image。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:sagemaker:[a-z0-9-]+:[0-9]{12}:model-package/[a-zA-Z0-9](-*[a-zA-Z0-9]){0,62}/[0-9]+$", var.model_package_arn))
    error_message = "model_package_arn must be a versioned model package ARN (arn:<partition>:sagemaker:<region>:<account>:model-package/<group>/<version>)."
  }
}

variable "execution_role_arn" {
  type        = string
  description = "model 執行用的 IAM role ARN（module 不建 role），要能讀模型 artifact、拉 image、用 `kms_key_arn`，instance variant 還要能建 VPC ENI。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "客戶管理 KMS key ARN（symmetric），必填。加密 endpoint configuration 的 ML storage volume 與 data capture 寫進 S3 的資料。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "variant" {
  type = object({
    instance = optional(object({
      instance_type          = string
      initial_instance_count = optional(number, 1)
    }))
    serverless = optional(object({
      memory_size_in_mb       = number
      max_concurrency         = number
      provisioned_concurrency = optional(number)
    }))
  })
  nullable    = false
  description = "唯一的 variant，`instance` 與 `serverless` 擇一。`instance`：`instance_type` 以 `ml.` 開頭，`initial_instance_count` 至少 1（預設 1），必須給 `vpc` 與 `deployment`。`serverless`：`memory_size_in_mb` 是 1024–6144 且是 1024 的倍數，`max_concurrency` 1–200，`provisioned_concurrency` 選填且不能大於 `max_concurrency`；不能給 `vpc`、`data_capture`，`enable_network_isolation` 要設成 `false`。"

  validation {
    condition     = (var.variant.instance != null) != (var.variant.serverless != null)
    error_message = "variant must set exactly one of instance or serverless."
  }

  validation {
    condition     = var.variant.instance == null || try(startswith(var.variant.instance.instance_type, "ml."), false)
    error_message = "variant.instance.instance_type must start with \"ml.\"."
  }

  validation {
    condition     = var.variant.instance == null || try(var.variant.instance.initial_instance_count >= 1 && var.variant.instance.initial_instance_count == floor(var.variant.instance.initial_instance_count), false)
    error_message = "variant.instance.initial_instance_count must be a whole number >= 1."
  }

  validation {
    condition     = var.variant.serverless == null || try(contains([1024, 2048, 3072, 4096, 5120, 6144], var.variant.serverless.memory_size_in_mb), false)
    error_message = "variant.serverless.memory_size_in_mb must be a multiple of 1024 between 1024 and 6144."
  }

  validation {
    condition     = var.variant.serverless == null || try(var.variant.serverless.max_concurrency >= 1 && var.variant.serverless.max_concurrency <= 200 && var.variant.serverless.max_concurrency == floor(var.variant.serverless.max_concurrency), false)
    error_message = "variant.serverless.max_concurrency must be a whole number between 1 and 200."
  }

  validation {
    condition = var.variant.serverless == null || try(
      var.variant.serverless.provisioned_concurrency == null ||
      (var.variant.serverless.provisioned_concurrency >= 1 && var.variant.serverless.provisioned_concurrency <= var.variant.serverless.max_concurrency && var.variant.serverless.provisioned_concurrency == floor(var.variant.serverless.provisioned_concurrency)),
    false)
    error_message = "variant.serverless.provisioned_concurrency must be a whole number between 1 and max_concurrency."
  }
}

variable "vpc" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default     = null
  description = "model container 所在的 VPC：`subnet_ids`、`security_group_ids` 各至少一個。instance variant 必填，serverless variant 必須是 `null`（serverless 不支援 VPC）。"

  validation {
    condition     = try(var.variant.instance == null, true) || var.vpc != null
    error_message = "vpc is required for an instance variant."
  }

  validation {
    condition     = try(var.variant.serverless == null, true) || var.vpc == null
    error_message = "vpc must be null for a serverless variant (serverless endpoints do not support VPC configuration)."
  }

  validation {
    condition     = var.vpc == null || try(length(var.vpc.subnet_ids) >= 1 && length(var.vpc.security_group_ids) >= 1, false)
    error_message = "vpc needs at least one subnet_ids entry and one security_group_ids entry."
  }
}

variable "enable_network_isolation" {
  type        = bool
  default     = true
  nullable    = false
  description = "model container 是否關掉對外網路（預設 `true`）。serverless variant 不支援，要明確設成 `false`。"

  validation {
    condition     = try(var.variant.serverless == null, true) || var.enable_network_isolation == false
    error_message = "enable_network_isolation must be false for a serverless variant (serverless endpoints do not support network isolation)."
  }
}

variable "data_capture" {
  type = object({
    destination_s3_uri  = string
    sampling_percentage = number
  })
  default     = null
  description = "記錄推論的請求與回應：`destination_s3_uri` 是 `s3://` 路徑，`sampling_percentage` 是 0–100 的整數。用 `kms_key_arn` 加密。`null` 不開；serverless variant 必須是 `null`。"

  validation {
    condition     = try(var.variant.serverless == null, true) || var.data_capture == null
    error_message = "data_capture must be null for a serverless variant (serverless endpoints do not support data capture)."
  }

  validation {
    condition     = var.data_capture == null || try(can(regex("^s3://[^/]+", var.data_capture.destination_s3_uri)), false)
    error_message = "data_capture.destination_s3_uri must start with s3://<bucket>."
  }

  validation {
    condition     = var.data_capture == null || try(var.data_capture.sampling_percentage >= 0 && var.data_capture.sampling_percentage <= 100 && var.data_capture.sampling_percentage == floor(var.data_capture.sampling_percentage), false)
    error_message = "data_capture.sampling_percentage must be a whole number between 0 and 100."
  }
}

variable "deployment" {
  type = object({
    blue_green = optional(object({
      traffic                              = string
      canary_size                          = optional(object({ type = string, value = number }))
      linear_step_size                     = optional(object({ type = string, value = number }))
      wait_interval_in_seconds             = optional(number, 600)
      termination_wait_in_seconds          = optional(number, 0)
      maximum_execution_timeout_in_seconds = optional(number)
    }))
    rolling = optional(object({
      maximum_batch_size                   = object({ type = string, value = number })
      rollback_maximum_batch_size          = optional(object({ type = string, value = number }))
      wait_interval_in_seconds             = optional(number, 600)
      maximum_execution_timeout_in_seconds = optional(number)
    }))
    rollback_alarm_names = list(string)
  })
  default     = null
  description = "更新 endpoint 的方式，`blue_green` 與 `rolling` 擇一，`rollback_alarm_names` 是 1–10 個 CloudWatch 告警名稱，烘烤期間任何一個進入 ALARM 就自動 rollback。`blue_green.traffic` 是 `ALL_AT_ONCE`、`CANARY`（要 `canary_size`）或 `LINEAR`（要 `linear_step_size`）；size 的 `type` 是 `INSTANCE_COUNT` 或 `CAPACITY_PERCENT`；`wait_interval_in_seconds` 是烘烤秒數，0–3600（預設 600）。instance variant 必填；serverless variant 選填，且只能用 `blue_green`（rolling 不支援 serverless）。"

  validation {
    condition     = try(var.variant.instance == null, true) || var.deployment != null
    error_message = "deployment is required for an instance variant."
  }

  validation {
    condition     = var.deployment == null || try((var.deployment.blue_green != null) != (var.deployment.rolling != null), false)
    error_message = "deployment must set exactly one of blue_green or rolling."
  }

  validation {
    condition     = var.deployment == null || try(length(var.deployment.rollback_alarm_names) >= 1 && length(var.deployment.rollback_alarm_names) <= 10 && alltrue([for a in var.deployment.rollback_alarm_names : length(a) > 0]), false)
    error_message = "deployment.rollback_alarm_names must list 1-10 non-empty CloudWatch alarm names."
  }

  validation {
    condition     = var.deployment == null || try(var.variant.serverless == null, true) || try(var.deployment.rolling == null, false)
    error_message = "deployment.rolling is not supported for a serverless variant; use blue_green."
  }

  validation {
    condition     = try(var.deployment.blue_green == null, true) || try(contains(["ALL_AT_ONCE", "CANARY", "LINEAR"], var.deployment.blue_green.traffic), false)
    error_message = "deployment.blue_green.traffic must be ALL_AT_ONCE, CANARY or LINEAR."
  }

  validation {
    condition = try(var.deployment.blue_green == null, true) || try(
      (var.deployment.blue_green.canary_size != null) == (var.deployment.blue_green.traffic == "CANARY") &&
      (var.deployment.blue_green.linear_step_size != null) == (var.deployment.blue_green.traffic == "LINEAR"),
    false)
    error_message = "deployment.blue_green needs canary_size only for CANARY and linear_step_size only for LINEAR."
  }

  validation {
    condition = var.deployment == null || try(alltrue([for s in [
      try(var.deployment.blue_green.canary_size, null),
      try(var.deployment.blue_green.linear_step_size, null),
      try(var.deployment.rolling.maximum_batch_size, null),
      try(var.deployment.rolling.rollback_maximum_batch_size, null),
      ] : contains(["INSTANCE_COUNT", "CAPACITY_PERCENT"], s.type) && s.value >= 1 && s.value == floor(s.value) if s != null
    ]), false)
    error_message = "every deployment size must have type INSTANCE_COUNT or CAPACITY_PERCENT and a whole value >= 1."
  }

  validation {
    condition = var.deployment == null || try(alltrue([for w in [
      try(var.deployment.blue_green.wait_interval_in_seconds, null),
      try(var.deployment.blue_green.termination_wait_in_seconds, null),
      try(var.deployment.rolling.wait_interval_in_seconds, null),
    ] : w >= 0 && w <= 3600 if w != null]), false)
    error_message = "deployment wait_interval_in_seconds and termination_wait_in_seconds must be between 0 and 3600."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "model、endpoint configuration、endpoint 的 tag；`Name` 由 module 加上。"
}
