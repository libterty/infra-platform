variable "name_prefix" {
  type        = string
  description = "source 與 destination 的名稱前綴，名稱是 `<name_prefix>-<key>`，最多 60 字元。"
}

variable "region" {
  type        = string
  default     = null
  description = "source、destination 與 delivery 建在哪個 region，例如 `us-east-1`；`null` 時跟著 provider 的 region。CloudFront distribution 的 source 必須建在 `us-east-1`。"
  validation {
    condition     = var.region == null ? true : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like us-east-1."
  }
}

variable "sources" {
  type = map(object({
    resource_arn = string
    log_type     = string
  }))
  default     = {}
  description = "delivery source，key 是短名。欄位：`resource_arn`（產生 log 的資源 ARN，任何支援 vended log delivery 的資源都可以，例如 ALB、EKS cluster、CloudFront distribution、AgentCore Runtime；必須帶 12 位數帳號，帳號是目前帳號或在 `allowed_account_ids` 裡，S3 bucket ARN 不帶帳號，是唯一例外）、`log_type`（服務定義的值，例如 `ALB_ACCESS_LOGS`、`S3_SERVER_ACCESS_LOGS`，1–255 個英數字或底線）。"
  validation {
    condition     = alltrue([for s in values(var.sources) : can(regex("^arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", s.resource_arn)) || can(regex(local.destination_arn_patterns.S3, s.resource_arn))])
    error_message = "Each source resource_arn must be an ARN that includes a 12-digit account ID, or an S3 bucket ARN."
  }
  validation {
    condition     = alltrue([for s in values(var.sources) : can(regex("^[A-Za-z0-9_]{1,255}$", s.log_type))])
    error_message = "log_type must be 1-255 letters, digits or underscores, as defined by the source service (for example ALB_ACCESS_LOGS)."
  }
  validation {
    condition     = alltrue([for k in keys(var.sources) : length("${var.name_prefix}-${k}") <= 60])
    error_message = "Each source name <name_prefix>-<key> must be at most 60 characters."
  }
}

variable "destinations" {
  type = map(object({
    type         = string
    resource_arn = optional(string)
  }))
  default     = {}
  description = "delivery destination，key 是短名。欄位：`type`（`CWL`、`S3`、`FH` 或 `XRAY`）、`resource_arn`（`CWL` 是 log group ARN、`S3` 是 bucket ARN、`FH` 是 delivery stream ARN，`XRAY` 必須是 `null`）。`CWL`、`FH` 的帳號必須是目前帳號或在 `allowed_account_ids` 裡；S3 bucket ARN 不帶帳號，不檢查。"
  validation {
    condition     = alltrue([for d in values(var.destinations) : contains(["CWL", "S3", "FH", "XRAY"], d.type)])
    error_message = "Destination type must be CWL, S3, FH or XRAY."
  }
  validation {
    condition = alltrue([for d in values(var.destinations) : d.type == "XRAY" ? d.resource_arn == null : (
      d.resource_arn == null ? false : can(regex(lookup(local.destination_arn_patterns, d.type, "^$"), d.resource_arn))
    )])
    error_message = "XRAY destinations must not set resource_arn; CWL needs a log group ARN, S3 a bucket ARN and FH a Firehose delivery stream ARN."
  }
  validation {
    condition     = alltrue([for k in keys(var.destinations) : length("${var.name_prefix}-${k}") <= 60])
    error_message = "Each destination name <name_prefix>-<key> must be at most 60 characters."
  }
}

variable "allowed_account_ids" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "除了目前帳號，source 與 `CWL`、`FH` 目的地還可以放在哪些帳號（12 位數字）。空的時候都必須在目前帳號。"
  validation {
    condition     = alltrue([for a in var.allowed_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "allowed_account_ids must contain 12-digit AWS account IDs."
  }
}

variable "deliveries" {
  type = map(object({
    source      = string
    destination = string
  }))
  default     = {}
  description = "delivery，key 是短名。欄位：`source`、`destination`，分別是 `sources`、`destinations` 裡存在的 key；同一組 source 與 destination 不能接兩次。"
  validation {
    condition     = alltrue([for d in values(var.deliveries) : contains(keys(var.sources), d.source) && contains(keys(var.destinations), d.destination)])
    error_message = "Every delivery must name an existing key in sources and in destinations."
  }
  validation {
    condition     = length(distinct([for d in values(var.deliveries) : "${d.source}/${d.destination}"])) == length(var.deliveries)
    error_message = "A source must not be delivered to the same destination twice."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "每個資源的 tag；source 與 destination 另外由 module 加上 `Name`。"
}
