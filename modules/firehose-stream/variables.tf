variable "name" {
  type        = string
  description = "delivery stream 名稱，1–64 字元，限英數字、`_`、`-`、`.`。"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars of letters, digits, underscores, hyphens or dots."
  }
}

variable "role_arn" {
  type        = string
  description = "Firehose 假設的 IAM role ARN，由呼叫端建立。同一個 role 用於讀來源 stream、寫 S3、寫 OpenSearch、建 VPC 內的 ENI 與寫 CloudWatch Logs；trust 要是 `firehose.amazonaws.com`。"

  validation {
    condition     = var.role_arn != null && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9_+=,.@/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:<partition>:iam::<account>:role/<name>)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "客戶管理的 KMS key ARN（symmetric），必填。Direct PUT 的 SSE、S3 物件加密與 module 建的 log group 都用這把 key；key policy 要讓 `role_arn` 與 CloudWatch Logs 能用它。"

  validation {
    condition     = var.kms_key_arn != null && can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>); aliases and bare key ids are not accepted."
  }
}

variable "source_stream_arn" {
  type        = string
  default     = null
  description = "來源 Kinesis Data Stream 的 ARN。`null` 是 Direct PUT，這時 module 會用 `kms_key_arn` 開 SSE；給了來源就不開 SSE（SSE 只支援 Direct PUT，at-rest 加密由來源 stream 負責）。"

  validation {
    condition     = var.source_stream_arn == null || can(regex("^arn:aws[a-z-]*:kinesis:[a-z0-9-]+:[0-9]{12}:stream/[a-zA-Z0-9_.-]{1,128}$", var.source_stream_arn))
    error_message = "source_stream_arn must be null (Direct PUT) or a Kinesis stream ARN (arn:<partition>:kinesis:<region>:<account>:stream/<name>)."
  }
}

variable "s3" {
  type = object({
    bucket_arn          = string
    prefix              = string
    error_output_prefix = optional(string)
    buffering_size      = optional(number, 64)
    buffering_interval  = optional(number, 900)
    compression         = optional(string, "GZIP")
  })
  description = "S3 設定，必填。沒給 `opensearch` 時是主要目的地（`extended_s3`）；給了 `opensearch` 時是失敗文件的備份（只備份失敗的）。`bucket_arn` 是 bucket 的 ARN（不含物件路徑）；`prefix` 可用 `!{timestamp:...}`，用了表達式就必須給 `error_output_prefix`，而且它要含 `!{firehose:error-output-type}`；`buffering_size` 單位 MiB（1–128，預設 64）；`buffering_interval` 單位秒（0–900，預設 900，事件觸發 ETL 靠它壓低觸發次數）；`compression` 預設 `GZIP`。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3.bucket_arn))
    error_message = "s3.bucket_arn must be an S3 bucket ARN without an object path (arn:<partition>:s3:::<bucket>)."
  }

  validation {
    condition     = !strcontains(var.s3.prefix, "!{firehose:error-output-type}")
    error_message = "s3.prefix must not contain !{firehose:error-output-type}; that expression is only valid in error_output_prefix."
  }

  # AWS: error_output_prefix may be null only when prefix has no expressions; with expressions in prefix the
  # console and the design require the error prefix to carry !{firehose:error-output-type}.
  validation {
    condition     = !strcontains(var.s3.prefix, "!{") || var.s3.error_output_prefix != null
    error_message = "s3.error_output_prefix is required when s3.prefix uses expressions such as !{timestamp:...}."
  }

  validation {
    condition     = !strcontains(var.s3.prefix, "!{") || (var.s3.error_output_prefix != null && strcontains(coalesce(var.s3.error_output_prefix, ""), "!{firehose:error-output-type}"))
    error_message = "s3.error_output_prefix must contain !{firehose:error-output-type} when s3.prefix uses expressions."
  }

  # AWS: an expression in error_output_prefix needs at least one !{firehose:error-output-type}.
  validation {
    condition     = var.s3.error_output_prefix == null || !strcontains(var.s3.error_output_prefix, "!{") || strcontains(var.s3.error_output_prefix, "!{firehose:error-output-type}")
    error_message = "s3.error_output_prefix must contain !{firehose:error-output-type} when it uses expressions."
  }

  validation {
    condition     = var.s3.buffering_interval >= 0 && var.s3.buffering_interval <= 900 && var.s3.buffering_interval == floor(var.s3.buffering_interval)
    error_message = "s3.buffering_interval must be a whole number of seconds between 0 and 900."
  }

  validation {
    condition     = var.s3.buffering_size >= 1 && var.s3.buffering_size <= 128 && var.s3.buffering_size == floor(var.s3.buffering_size)
    error_message = "s3.buffering_size must be a whole number of MiB between 1 and 128."
  }

  validation {
    condition     = contains(["GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY", "UNCOMPRESSED"], var.s3.compression)
    error_message = "s3.compression must be GZIP, ZIP, Snappy, HADOOP_SNAPPY or UNCOMPRESSED."
  }
}

variable "opensearch" {
  type = object({
    domain_arn            = string
    index_name            = string
    index_rotation_period = optional(string, "OneDay")
    subnet_ids            = optional(set(string), [])
    security_group_ids    = optional(set(string), [])
    retry_seconds         = optional(number, 300)
  })
  default     = null
  description = "OpenSearch 目的地；`null` 就是 S3 目的地。domain 一定在 VPC 內，所以 `subnet_ids`（1–16 個）與 `security_group_ids`（1–5 個）必填；Firehose 會在這些 subnet 建 ENI，role 要有建 ENI 的 `ec2:*` 權限，建好後不能收回。`index_rotation_period` 為 `NoRotation`、`OneHour`、`OneDay`、`OneWeek`、`OneMonth`；`retry_seconds` 0–7200。"

  validation {
    condition     = var.opensearch == null || can(regex("^arn:aws[a-z-]*:es:[a-z0-9-]+:[0-9]{12}:domain/[a-z][-0-9a-z]{2,27}$", var.opensearch.domain_arn))
    error_message = "opensearch.domain_arn must be an OpenSearch domain ARN (arn:<partition>:es:<region>:<account>:domain/<name>)."
  }

  validation {
    condition     = var.opensearch == null || can(regex("^[a-z0-9][a-z0-9._-]{0,79}$", var.opensearch.index_name))
    error_message = "opensearch.index_name must be 1-80 chars of lowercase letters, digits, dots, underscores or hyphens, starting with a letter or digit."
  }

  validation {
    condition     = var.opensearch == null || contains(["NoRotation", "OneHour", "OneDay", "OneWeek", "OneMonth"], var.opensearch.index_rotation_period)
    error_message = "opensearch.index_rotation_period must be NoRotation, OneHour, OneDay, OneWeek or OneMonth."
  }

  validation {
    condition     = var.opensearch == null || (var.opensearch.retry_seconds >= 0 && var.opensearch.retry_seconds <= 7200 && var.opensearch.retry_seconds == floor(var.opensearch.retry_seconds))
    error_message = "opensearch.retry_seconds must be a whole number of seconds between 0 and 7200."
  }

  # The domain is VPC-only (design K4), so a destination without VPC settings can never deliver.
  validation {
    condition     = var.opensearch == null || (length(var.opensearch.subnet_ids) >= 1 && length(var.opensearch.subnet_ids) <= 16)
    error_message = "opensearch.subnet_ids must hold 1-16 subnet ids; the OpenSearch destination must have VPC settings."
  }

  validation {
    condition     = var.opensearch == null || (length(var.opensearch.security_group_ids) >= 1 && length(var.opensearch.security_group_ids) <= 5)
    error_message = "opensearch.security_group_ids must hold 1-5 security group ids; the OpenSearch destination must have VPC settings."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  nullable    = false
  description = "module 自己建的 log group 的保留天數，必須是 CloudWatch Logs 接受的值（預設 30）。"

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ... 3653)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "資源的 tag；`Name` 由 module 加上。"
}
