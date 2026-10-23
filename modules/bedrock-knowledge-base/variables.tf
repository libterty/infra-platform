variable "name" {
  type        = string
  description = "KB 的完整名稱。字母、數字、`-`、`_`，頭尾是字母或數字，最多 100 字元。"

  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z_-]{0,98}[0-9A-Za-z])?$", var.name))
    error_message = "name must be letters, digits, hyphens or underscores, at most 100 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "KB 的說明。"
}

variable "role_arn" {
  type        = string
  description = "Bedrock KB service role ARN（範本由 `iam-base` 建），可以帶 path，但每段不能是空的。這個 module 不建 IAM。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN; path segments must not be empty."
  }
}

variable "embedding_model_arn" {
  type        = string
  description = "嵌入模型的 foundation-model ARN，不能含 `*`。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+::foundation-model/[A-Za-z0-9._:/-]+$", var.embedding_model_arn))
    error_message = "embedding_model_arn must be a foundation-model ARN without wildcards."
  }
}

variable "embedding_dimensions" {
  type        = number
  description = "向量維度，正整數，必須等於表裡向量欄的 `vector(N)`。"

  validation {
    condition     = var.embedding_dimensions > 0 && floor(var.embedding_dimensions) == var.embedding_dimensions
    error_message = "embedding_dimensions must be a positive whole number."
  }
}

variable "aurora" {
  type = object({
    cluster_arn            = string
    credentials_secret_arn = string
    database_name          = string
    table_name             = string
    field_mapping = optional(object({
      primary_key_field     = optional(string, "id")
      vector_field          = optional(string, "embedding")
      text_field            = optional(string, "chunks")
      metadata_field        = optional(string, "metadata")
      custom_metadata_field = optional(string)
    }), {})
  })
  description = "Aurora PostgreSQL 向量儲存，表與欄位由專案的 migration 建。欄位：`cluster_arn`（Aurora cluster ARN，不收 DB instance ARN）、`credentials_secret_arn`（KB 專用資料庫帳號的 secret 完整 ARN，含 6 字元尾碼，值是 `{\"username\",\"password\"}`，**不要給 master secret**）、`database_name`（小寫識別字）、`table_name`（`<schema>.<table>` 或 `<table>`，每段小寫識別字）、`field_mapping`（選填，預設 `{}`；五個欄位名稱與預設見〈部署前要先完成的事〉的對照表，都是小寫識別字、彼此不重複，`custom_metadata_field` 預設 `null`，不送）。`cluster_arn` 與 `credentials_secret_arn` 必須在目前的帳號與 region。"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:rds:[a-z0-9-]+:[0-9]{12}:cluster:[A-Za-z][A-Za-z0-9-]*$", var.aurora.cluster_arn))
    error_message = "aurora.cluster_arn must be an Aurora cluster ARN (arn:aws:rds:<region>:<account>:cluster:<id>), not a DB instance ARN."
  }

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@!-]+-[A-Za-z0-9]{6}$", var.aurora.credentials_secret_arn))
    error_message = "aurora.credentials_secret_arn must be the exact Secrets Manager secret ARN, including the 6 character suffix and no wildcards."
  }

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.aurora.database_name))
    error_message = "aurora.database_name must be a lowercase identifier."
  }

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}(\\.[a-z_][a-z0-9_]{0,62})?$", var.aurora.table_name))
    error_message = "aurora.table_name must be <schema>.<table> or <table>, each part a lowercase identifier."
  }

  validation {
    condition = alltrue([
      for f in [
        var.aurora.field_mapping.primary_key_field,
        var.aurora.field_mapping.vector_field,
        var.aurora.field_mapping.text_field,
        var.aurora.field_mapping.metadata_field,
        var.aurora.field_mapping.custom_metadata_field,
      ] : f == null || can(regex("^[a-z_][a-z0-9_]{0,62}$", f))
    ])
    error_message = "aurora.field_mapping fields must be lowercase identifiers."
  }

  validation {
    condition = length(compact([
      var.aurora.field_mapping.primary_key_field,
      var.aurora.field_mapping.vector_field,
      var.aurora.field_mapping.text_field,
      var.aurora.field_mapping.metadata_field,
      var.aurora.field_mapping.custom_metadata_field,
      ])) == length(distinct(compact([
        var.aurora.field_mapping.primary_key_field,
        var.aurora.field_mapping.vector_field,
        var.aurora.field_mapping.text_field,
        var.aurora.field_mapping.metadata_field,
        var.aurora.field_mapping.custom_metadata_field,
    ])))
    error_message = "aurora.field_mapping fields must be distinct."
  }
}

variable "data_sources" {
  type = map(object({
    bucket_arn              = string
    inclusion_prefixes      = optional(set(string), [])
    bucket_owner_account_id = string
    data_deletion_policy    = optional(string, "RETAIN")
    chunking = optional(object({
      strategy           = optional(string, "FIXED_SIZE")
      max_tokens         = optional(number, 300)
      overlap_percentage = optional(number, 20)
    }), {})
  }))
  default     = {}
  description = "S3 data source，key 是 data source 名稱（規則同 `name`）。欄位見〈`data_sources` 欄位〉。"

  validation {
    condition     = alltrue([for k in keys(var.data_sources) : can(regex("^[0-9A-Za-z]([0-9A-Za-z_-]{0,98}[0-9A-Za-z])?$", k))])
    error_message = "data_sources keys are data source names: letters, digits, hyphens or underscores, at most 100 chars."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", d.bucket_arn))])
    error_message = "data_sources[*].bucket_arn must be an S3 bucket ARN."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : can(regex("^[0-9]{12}$", d.bucket_owner_account_id))])
    error_message = "data_sources[*].bucket_owner_account_id must be a 12 digit account ID."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : contains(["RETAIN", "DELETE"], d.data_deletion_policy)])
    error_message = "data_sources[*].data_deletion_policy must be RETAIN or DELETE."
  }

  validation {
    condition     = alltrue(flatten([for d in values(var.data_sources) : [for p in d.inclusion_prefixes : !startswith(p, "/")]]))
    error_message = "data_sources[*].inclusion_prefixes must not start with /."
  }

  # FIXED_SIZE and NONE only; HIERARCHICAL and SEMANTIC are out of scope for this version.
  validation {
    condition     = alltrue([for d in values(var.data_sources) : contains(["FIXED_SIZE", "NONE"], d.chunking.strategy)])
    error_message = "data_sources[*].chunking.strategy must be FIXED_SIZE or NONE."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : d.chunking.max_tokens > 0])
    error_message = "data_sources[*].chunking.max_tokens must be greater than 0."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : d.chunking.overlap_percentage >= 1 && d.chunking.overlap_percentage <= 99])
    error_message = "data_sources[*].chunking.overlap_percentage must be between 1 and 99."
  }
}

variable "allowed_account_ids" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "目前帳號以外、允許擁有 data source bucket 的帳號（12 位數字）。空集合表示只收同帳號的 bucket。"

  validation {
    condition     = alltrue([for a in var.allowed_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "allowed_account_ids must contain 12 digit account IDs."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "data source ingestion 暫存資料（server-side encryption）用的 KMS key ARN（`key/<uuid>` 或 `key/mrk-<32 碼>`，不收 alias 與 `*`）。`null` 時用 AWS 管理的 key。"

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f-]{36})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<uuid>), not an alias or a wildcard."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "套用到 KB 的 tag，另外自動加 `Name`；data source 沒有 tag。"
}
