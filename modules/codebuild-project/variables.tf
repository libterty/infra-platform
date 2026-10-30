variable "name" {
  type        = string
  description = "建置專案名稱，2–255 字元，限英數字、`-`、`_`，英數字開頭。log group 預設名稱是 `/aws/codebuild/<name>`。"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,254}$", var.name))
    error_message = "name must be 2-255 chars of letters, digits, hyphens or underscores, starting with a letter or digit."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "建置專案的說明，最多 255 字元；`null`（預設）不設。"

  validation {
    condition     = var.description == null || try(length(var.description) <= 255, false)
    error_message = "description must be at most 255 characters."
  }
}

variable "service_role_arn" {
  type        = string
  description = "建置專案的 service role ARN，用 `iam-role` 建。至少要能寫這個 log group、讀寫 pipeline 的 artifact bucket、用 `encryption_key_arn` 這把 key；buildspec 會用這個 role 的全部權限，每個元件各用一個 role。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.service_role_arn))
    error_message = "service_role_arn must be an IAM role ARN."
  }
}

variable "buildspec" {
  type        = string
  default     = null
  description = "buildspec：source repo 裡的路徑（例如 `ci/api/buildspec.yml`）或 inline YAML；`null`（預設）用 repo 根目錄的 `buildspec.yml`。"

  validation {
    condition     = var.buildspec == null || try(length(trimspace(var.buildspec)) > 0, false)
    error_message = "buildspec must be null or a non-empty path or YAML document."
  }
}

variable "environment" {
  type = object({
    compute_type    = optional(string, "BUILD_GENERAL1_SMALL")
    image           = optional(string, "aws/codebuild/amazonlinux-aarch64-standard:3.0")
    type            = optional(string, "ARM_CONTAINER")
    privileged_mode = optional(bool, false)
  })
  default     = {}
  nullable    = false
  description = "建置環境。欄位：`compute_type`（`BUILD_GENERAL1_SMALL`（預設）、`_MEDIUM`、`_LARGE`、`_XLARGE`、`_2XLARGE`）、`image`（預設 `aws/codebuild/amazonlinux-aarch64-standard:3.0`）、`type`（`ARM_CONTAINER`（預設）或 `LINUX_CONTAINER`，要跟映像的架構一致）、`privileged_mode`（預設 `false`；在建置裡跑 `docker build` 的專案要開）。"

  validation {
    condition     = contains(["BUILD_GENERAL1_SMALL", "BUILD_GENERAL1_MEDIUM", "BUILD_GENERAL1_LARGE", "BUILD_GENERAL1_XLARGE", "BUILD_GENERAL1_2XLARGE"], var.environment.compute_type)
    error_message = "environment.compute_type must be BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_XLARGE or BUILD_GENERAL1_2XLARGE."
  }

  validation {
    condition     = contains(["ARM_CONTAINER", "LINUX_CONTAINER"], var.environment.type)
    error_message = "environment.type must be ARM_CONTAINER or LINUX_CONTAINER."
  }

  validation {
    condition     = length(trimspace(var.environment.image)) > 0
    error_message = "environment.image must not be empty."
  }

  # The architecture is chosen by type, not compute_type, so a curated image must match type or the build fails at start.
  validation {
    condition = (
      !(strcontains(var.environment.image, "aarch64") && var.environment.type != "ARM_CONTAINER") &&
      !((strcontains(var.environment.image, "x86_64") || startswith(var.environment.image, "aws/codebuild/standard:")) && var.environment.type != "LINUX_CONTAINER")
    )
    error_message = "environment.image and environment.type must match: aarch64 images need ARM_CONTAINER, x86_64 and aws/codebuild/standard images need LINUX_CONTAINER."
  }
}

variable "environment_variables" {
  type = map(object({
    value = string
    type  = optional(string, "PLAINTEXT")
  }))
  default     = {}
  nullable    = false
  description = "建置的環境變數，名稱對應 `{ value, type }`。`type` 是 `PLAINTEXT`（預設）、`PARAMETER_STORE`（`value` 是參數名稱）、`SECRETS_MANAGER`（`value` 是 `<secret-id>:<json-key>` 這類參照）。名稱要以字母或底線開頭，限英數字與底線；`PLAINTEXT` 的名稱像 secret（含 `PASSWORD`、`SECRET`、`TOKEN`、`KEY`）會被拒，要改用另外兩種類型。"

  validation {
    condition     = alltrue([for k in keys(var.environment_variables) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "environment_variables names must start with a letter or underscore and contain only letters, digits and underscores."
  }

  validation {
    condition     = alltrue([for v in values(var.environment_variables) : contains(["PLAINTEXT", "PARAMETER_STORE", "SECRETS_MANAGER"], v.type)])
    error_message = "environment_variables type must be PLAINTEXT, PARAMETER_STORE or SECRETS_MANAGER."
  }

  # PLAINTEXT values are visible in the project definition, build logs metadata and Terraform state.
  validation {
    condition     = alltrue([for k, v in var.environment_variables : v.type != "PLAINTEXT" || !can(regex("(PASSWORD|SECRET|TOKEN|KEY)", upper(k)))])
    error_message = "PLAINTEXT environment_variables must not look like secrets (PASSWORD, SECRET, TOKEN, KEY); use PARAMETER_STORE or SECRETS_MANAGER."
  }
}

variable "encryption_key_arn" {
  type        = string
  description = "加密建置輸出 artifact 的客戶管理 KMS key ARN（`key/<id>`，不接受 alias），必填。通常跟 pipeline artifact bucket 用同一把。"

  validation {
    condition     = var.encryption_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.encryption_key_arn))
    error_message = "encryption_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "log_group_name" {
  type        = string
  default     = null
  description = "module 建的 log group 名稱，1–512 字元，限英數字與 `.`、`-`、`_`、`/`、`#`；`null`（預設）用 `/aws/codebuild/<name>`。"

  validation {
    condition     = var.log_group_name == null || can(regex("^[A-Za-z0-9._/#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name must be 1-512 chars of letters, digits, '.', '-', '_', '/' or '#'."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`），不接受 `0`（永不過期）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "log group 的客戶自管 KMS key ARN（`key/<id>`，不接受 alias）。key policy 必須允許 `logs.<region>.amazonaws.com`。"

  validation {
    condition     = var.log_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (key/<id>), not an alias."
  }
}

variable "build_timeout" {
  type        = number
  default     = 30
  description = "單次建置的逾時分鐘數，5–2160 的整數。"

  validation {
    condition     = var.build_timeout == floor(var.build_timeout) && var.build_timeout >= 5 && var.build_timeout <= 2160
    error_message = "build_timeout must be a whole number from 5 to 2160."
  }
}

variable "queued_timeout" {
  type        = number
  default     = 60
  description = "建置在佇列等待的逾時分鐘數，5–480 的整數。"

  validation {
    condition     = var.queued_timeout == floor(var.queued_timeout) && var.queued_timeout >= 5 && var.queued_timeout <= 480
    error_message = "queued_timeout must be a whole number from 5 to 480."
  }
}

variable "concurrent_build_limit" {
  type        = number
  default     = 1
  description = "同時執行的建置數上限，至少 1 的整數。預設 `1`，同一個專案的部署不會重疊。"

  validation {
    condition     = var.concurrent_build_limit == floor(var.concurrent_build_limit) && var.concurrent_build_limit >= 1
    error_message = "concurrent_build_limit must be a whole number of at least 1."
  }
}

variable "cache_modes" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "本機快取模式，值是 `LOCAL_DOCKER_LAYER_CACHE`、`LOCAL_SOURCE_CACHE`、`LOCAL_CUSTOM_CACHE`，不可重複；`[]`（預設）時不快取。`LOCAL_DOCKER_LAYER_CACHE` 要搭配 `environment.privileged_mode = true`。"

  validation {
    condition     = alltrue([for m in var.cache_modes : contains(["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE", "LOCAL_CUSTOM_CACHE"], m)]) && length(distinct(var.cache_modes)) == length(var.cache_modes)
    error_message = "cache_modes must list distinct values of LOCAL_DOCKER_LAYER_CACHE, LOCAL_SOURCE_CACHE and LOCAL_CUSTOM_CACHE."
  }

  validation {
    condition     = !contains(var.cache_modes, "LOCAL_DOCKER_LAYER_CACHE") || var.environment.privileged_mode
    error_message = "LOCAL_DOCKER_LAYER_CACHE needs environment.privileged_mode = true."
  }
}

variable "region" {
  type        = string
  default     = null
  description = "建置專案與 log group 所在的 region；`null`（預設）用 provider 的 region。"

  validation {
    condition     = var.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.region))
    error_message = "region must be an AWS region such as us-east-1."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "建置專案與 log group 的 tag；`Name` 由 module 加上。"
}
