variable "name" {
  type        = string
  description = "Knowledge base name."

  validation {
    condition     = can(regex("^[0-9A-Za-z]([0-9A-Za-z_-]{0,98}[0-9A-Za-z])?$", var.name))
    error_message = "name must be letters, digits, hyphens or underscores, at most 100 chars."
  }
}

variable "description" {
  type        = string
  default     = null
  description = "Knowledge base description."
}

variable "role_arn" {
  type        = string
  description = "Bedrock knowledge base service role ARN. This module does not create IAM."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN."
  }
}

variable "embedding_model_arn" {
  type        = string
  description = "Embedding foundation model ARN."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+::foundation-model/.+$", var.embedding_model_arn))
    error_message = "embedding_model_arn must be a foundation-model ARN."
  }
}

variable "embedding_dimensions" {
  type        = number
  description = "Must equal the vector(N) size of the table's vector column."

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
  description = "Aurora PostgreSQL vector store. credentials_secret_arn is the secret of a dedicated knowledge base database user, never the master user secret. The table and columns are created by the project's migration."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:rds:[a-z0-9-]+:[0-9]{12}:cluster:[A-Za-z][A-Za-z0-9-]*$", var.aurora.cluster_arn))
    error_message = "aurora.cluster_arn must be an Aurora cluster ARN (arn:aws:rds:<region>:<account>:cluster:<id>), not a DB instance ARN."
  }

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.aurora.credentials_secret_arn))
    error_message = "aurora.credentials_secret_arn must be a Secrets Manager secret ARN."
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
    bucket_owner_account_id = optional(string)
    data_deletion_policy    = optional(string, "RETAIN")
    chunking = optional(object({
      strategy           = optional(string, "FIXED_SIZE")
      max_tokens         = optional(number, 300)
      overlap_percentage = optional(number, 20)
    }), {})
  }))
  default     = {}
  description = "S3 data sources keyed by data source name. data_deletion_policy RETAIN keeps vectors when a data source is deleted."

  validation {
    condition     = alltrue([for k in keys(var.data_sources) : can(regex("^[0-9A-Za-z]([0-9A-Za-z_-]{0,98}[0-9A-Za-z])?$", k))])
    error_message = "data_sources keys are data source names: letters, digits, hyphens or underscores, at most 100 chars."
  }

  validation {
    condition     = alltrue([for d in values(var.data_sources) : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", d.bucket_arn))])
    error_message = "data_sources[*].bucket_arn must be an S3 bucket ARN."
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

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key for transient data during ingestion (data source server-side encryption)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the knowledge base."
}
