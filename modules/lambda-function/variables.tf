variable "name" {
  type        = string
  description = "function 名稱，2–64 字元，限小寫英數字與連字號，字母開頭。log group 名稱為 `/aws/lambda/<name>`。"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,63}$", var.name))
    error_message = "name must be 2-64 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "image_uri" {
  type        = string
  description = "ECR image，要帶明確 tag（不可 `latest`）或 sha256 digest。tag 由 Terraform 管：換版就改這裡再 apply。"
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9._/-]+(:[A-Za-z0-9_.-]{1,128}|@sha256:[0-9a-f]{64})$", var.image_uri)) && !endswith(lower(var.image_uri), ":latest")
    error_message = "image_uri must be an ECR image with an explicit tag (not latest) or a sha256 digest."
  }
}

variable "role_arn" {
  type        = string
  description = "execution role 的 ARN，用 `iam-role` 建。需要這個 log group 的寫入權限；給 `vpc` 時還需要建立 network interface 的權限。"
  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN."
  }
}

variable "architectures" {
  type        = list(string)
  default     = ["arm64"]
  description = "剛好一個：`arm64` 或 `x86_64`，要跟 image 建置的架構一致。"
  validation {
    condition     = length(var.architectures) == 1 && contains(["arm64", "x86_64"], var.architectures[0])
    error_message = "architectures must be [\"arm64\"] or [\"x86_64\"]."
  }
}

variable "memory_size" {
  type        = number
  default     = 512
  description = "記憶體（MB），128–10240 的整數。"
  validation {
    condition     = var.memory_size == floor(var.memory_size) && var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be a whole number from 128 to 10240."
  }
}

variable "timeout" {
  type        = number
  default     = 30
  description = "逾時秒數，1–900 的整數。"
  validation {
    condition     = var.timeout == floor(var.timeout) && var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be a whole number from 1 to 900."
  }
}

variable "reserved_concurrent_executions" {
  type        = number
  default     = null
  description = "保留的並行數，不小於 0 的整數；`null` 時不保留，`0` 時 function 完全不能被呼叫。"
  validation {
    condition     = var.reserved_concurrent_executions == null ? true : (var.reserved_concurrent_executions == floor(var.reserved_concurrent_executions) && var.reserved_concurrent_executions >= 0)
    error_message = "reserved_concurrent_executions must be null or a whole number of at least 0."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "一般環境變數，名稱要以字母開頭，限英數字與底線。secret 放 Secrets Manager，這裡只傳 ARN：名稱像 secret（含 `SECRET`、`PASSWORD`、`PASSWD`、`TOKEN`、`API_KEY`、`PRIVATE_KEY`、`CREDENTIAL`）會被拒，除非名稱以 `_ARN` 結尾且值是 ARN。"
  validation {
    condition     = alltrue([for k in keys(var.environment) : can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", k))])
    error_message = "environment names must start with a letter and contain only letters, digits and underscores."
  }
  # Environment variables are readable through the control plane and stored in state in plain text.
  validation {
    condition = alltrue([for k, v in var.environment :
      !can(regex("(SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL)", upper(k))) ||
      (endswith(upper(k), "_ARN") && startswith(v, "arn:"))
    ])
    error_message = "environment names must not look like secrets (SECRET, PASSWORD, PASSWD, TOKEN, API_KEY, PRIVATE_KEY, CREDENTIAL). Secrets belong in Secrets Manager; pass only the secret ARN, in a name ending in _ARN."
  }
}

variable "vpc" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default     = null
  description = "把 function 接進 VPC；`null` 時不進 VPC。欄位：`subnet_ids`（`subnet-…` 格式）、`security_group_ids`（`sg-…` 格式），各至少一個。"
  validation {
    condition     = var.vpc == null ? true : (length(var.vpc.subnet_ids) > 0 && length(var.vpc.security_group_ids) > 0)
    error_message = "vpc needs at least one subnet ID and one security group ID."
  }
  validation {
    condition = var.vpc == null ? true : (
      alltrue([for s in var.vpc.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) &&
      alltrue([for s in var.vpc.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    )
    error_message = "vpc.subnet_ids must look like subnet-0123456789abcdef0 and vpc.security_group_ids like sg-0123456789abcdef0."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "function log group 的保留天數，必須是 CloudWatch Logs 接受的值（例如 `1`、`7`、`30`、`365`），不接受 `0`（永不過期）。"
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

variable "log_format" {
  type        = string
  default     = "Text"
  description = "log 格式，`Text` 或 `JSON`。"
  validation {
    condition     = contains(["Text", "JSON"], var.log_format)
    error_message = "log_format must be Text or JSON."
  }
}

variable "permissions" {
  type = map(object({
    principal      = string
    source_arn     = string
    source_account = optional(string)
    action         = optional(string, "lambda:InvokeFunction")
  }))
  default     = {}
  nullable    = false
  description = "statement id（1–100 字元，限英數字、`_`、`-`）對應可呼叫 function 的對象。欄位：`principal`（AWS 服務，`*.amazonaws.com`，不可有萬用字元）、`source_arn`（必填，resource 部分不可以萬用字元開頭）、`source_account`（12 位數帳號 ID；`s3.amazonaws.com` 必填，因為 bucket ARN 沒有帳號，避免 confused deputy）、`action`（預設 `lambda:InvokeFunction`，單一 `lambda:` action，不可有萬用字元）。"
  validation {
    condition     = alltrue([for k in keys(var.permissions) : can(regex("^[A-Za-z0-9_-]{1,100}$", k))])
    error_message = "Keys are statement ids: 1-100 chars of letters, digits, _ or -."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", p.principal))])
    error_message = "principal must be an AWS service principal such as events.amazonaws.com; no wildcards, accounts or other domains."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]*:[^*\\s]\\S*$", p.source_arn))])
    error_message = "source_arn is required and must be an ARN that does not start its resource part with a wildcard."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : p.source_account == null ? true : can(regex("^[0-9]{12}$", p.source_account))])
    error_message = "source_account must be a 12-digit AWS account ID."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : p.principal != "s3.amazonaws.com" || p.source_account != null])
    error_message = "s3.amazonaws.com needs source_account: a bucket ARN has no account ID, so without it any account's bucket with that name could invoke the function."
  }
  validation {
    condition     = alltrue([for p in values(var.permissions) : can(regex("^lambda:[A-Za-z]+$", p.action))])
    error_message = "action must be a single lambda: action such as lambda:InvokeFunction; no wildcards."
  }
}

variable "alias" {
  type        = string
  default     = null
  description = "alias 名稱，1–128 字元，限英數字、`-`、`_`，不能全是數字。給了就開 `publish`，每次 apply 改到 function 都會發布新版本，alias 指到最新發布的版本；`null` 時不發布版本也不建 alias。"
  validation {
    condition     = var.alias == null ? true : can(regex("^[A-Za-z0-9_-]{1,128}$", var.alias)) && !can(regex("^[0-9]+$", var.alias))
    error_message = "alias must be 1-128 chars of letters, digits, - or _, and must not be all digits."
  }
}

variable "pipeline_managed" {
  type        = bool
  default     = false
  nullable    = false
  description = "`true` 時程式碼版本交給 pipeline：function 忽略 `image_uri` 的變動（`image_uri` 只用在第一次建立），alias 忽略 `function_version` 與 `routing_config`。必須搭配 `alias`。"
  validation {
    condition     = !var.pipeline_managed || var.alias != null
    error_message = "pipeline_managed needs alias: the pipeline deploys by moving the alias."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "function 與 log group 的 tag；`Name` 由 module 加上。"
}
