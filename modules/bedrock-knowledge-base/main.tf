data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = var.name
  description = var.description
  role_arn    = var.role_arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions = var.embedding_dimensions
        }
      }
    }
  }

  # Bedrock reaches Aurora through the RDS Data API; the table and columns must already exist (project migration).
  storage_configuration {
    type = "RDS"

    rds_configuration {
      resource_arn           = var.aurora.cluster_arn
      credentials_secret_arn = var.aurora.credentials_secret_arn
      database_name          = var.aurora.database_name
      table_name             = var.aurora.table_name

      field_mapping {
        primary_key_field     = var.aurora.field_mapping.primary_key_field
        vector_field          = var.aurora.field_mapping.vector_field
        text_field            = var.aurora.field_mapping.text_field
        metadata_field        = var.aurora.field_mapping.metadata_field
        custom_metadata_field = var.aurora.field_mapping.custom_metadata_field
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition = (
        try(split(":", var.aurora.cluster_arn)[3], "") == local.region &&
        try(split(":", var.aurora.cluster_arn)[4], "") == local.account_id
      )
      error_message = "aurora.cluster_arn must be in the current account and region."
    }

    precondition {
      condition = (
        try(split(":", var.aurora.credentials_secret_arn)[3], "") == local.region &&
        try(split(":", var.aurora.credentials_secret_arn)[4], "") == local.account_id
      )
      error_message = "aurora.credentials_secret_arn must be in the current account and region."
    }
  }
}

resource "aws_bedrockagent_data_source" "this" {
  for_each = var.data_sources

  name                 = each.key
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this.id
  data_deletion_policy = each.value.data_deletion_policy

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn              = each.value.bucket_arn
      bucket_owner_account_id = each.value.bucket_owner_account_id
      inclusion_prefixes      = length(each.value.inclusion_prefixes) > 0 ? each.value.inclusion_prefixes : null
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = each.value.chunking.strategy

      dynamic "fixed_size_chunking_configuration" {
        for_each = each.value.chunking.strategy == "FIXED_SIZE" ? [each.value.chunking] : []
        content {
          max_tokens         = fixed_size_chunking_configuration.value.max_tokens
          overlap_percentage = fixed_size_chunking_configuration.value.overlap_percentage
        }
      }
    }
  }

  dynamic "server_side_encryption_configuration" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      kms_key_arn = server_side_encryption_configuration.value
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.bucket_owner_account_id == local.account_id || contains(var.allowed_account_ids, each.value.bucket_owner_account_id)
      error_message = "data_sources[*].bucket_owner_account_id must be the current account or listed in allowed_account_ids."
    }
  }
}
