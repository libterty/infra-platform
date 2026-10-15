mock_provider "aws" {
  mock_resource "aws_bedrockagent_knowledge_base" {
    defaults = {
      id  = "KBID000001"
      arn = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"
    }
  }
  mock_resource "aws_bedrockagent_data_source" {
    defaults = {
      id             = "DSID000001,KBID000001"
      data_source_id = "DSID000001"
    }
  }
}

variables {
  name                 = "alpha-dev-docs"
  role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb"
  embedding_model_arn  = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
  embedding_dimensions = 1024
  aurora = {
    cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
    database_name          = "app"
    table_name             = "bedrock_integration.bedrock_kb"
  }
}

run "vector_knowledge_base_on_rds" {
  command = plan

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.name == "alpha-dev-docs" && aws_bedrockagent_knowledge_base.this.role_arn == var.role_arn
    error_message = "name and role_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].type == "VECTOR"
    error_message = "knowledge_base_configuration.type must be VECTOR"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].vector_knowledge_base_configuration[0].embedding_model_arn == var.embedding_model_arn
    error_message = "embedding_model_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].vector_knowledge_base_configuration[0].embedding_model_configuration[0].bedrock_embedding_model_configuration[0].dimensions == 1024
    error_message = "dimensions must follow embedding_dimensions"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.storage_configuration[0].type == "RDS"
    error_message = "storage_configuration.type must be RDS"
  }
  assert {
    condition = (
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].resource_arn == var.aurora.cluster_arn &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].credentials_secret_arn == var.aurora.credentials_secret_arn &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].database_name == "app" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].table_name == "bedrock_integration.bedrock_kb"
    )
    error_message = "rds_configuration must follow aurora"
  }
  assert {
    condition     = length(aws_bedrockagent_data_source.this) == 0
    error_message = "No data source is created when data_sources is empty"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.description == null
    error_message = "description must default to null"
  }
}

run "field_mapping_defaults_without_custom_metadata" {
  command = plan

  assert {
    condition = (
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].primary_key_field == "id" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].vector_field == "embedding" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].text_field == "chunks" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].metadata_field == "metadata"
    )
    error_message = "field_mapping must default to id, embedding, chunks, metadata"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].custom_metadata_field == null
    error_message = "custom_metadata_field must not be sent by default"
  }
}

run "field_mapping_follows_input" {
  command = plan

  variables {
    embedding_dimensions = 256
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "kb"
      table_name             = "kb_chunks"
      field_mapping = {
        primary_key_field     = "chunk_id"
        vector_field          = "vec"
        text_field            = "body"
        metadata_field        = "meta"
        custom_metadata_field = "custom_metadata"
      }
    }
    description = "Product manuals"
  }

  assert {
    condition = (
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].primary_key_field == "chunk_id" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].vector_field == "vec" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].text_field == "body" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].metadata_field == "meta" &&
      aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].field_mapping[0].custom_metadata_field == "custom_metadata"
    )
    error_message = "field_mapping must follow the input, including custom_metadata_field"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].database_name == "kb" && aws_bedrockagent_knowledge_base.this.storage_configuration[0].rds_configuration[0].table_name == "kb_chunks"
    error_message = "database_name and table_name must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].vector_knowledge_base_configuration[0].embedding_model_configuration[0].bedrock_embedding_model_configuration[0].dimensions == 256
    error_message = "dimensions must follow embedding_dimensions"
  }
  assert {
    condition     = aws_bedrockagent_knowledge_base.this.description == "Product manuals"
    error_message = "description must follow the input"
  }
}

run "s3_data_sources" {
  command = plan

  variables {
    data_sources = {
      manuals = {
        bucket_arn         = "arn:aws:s3:::alpha-dev-kb-docs-111111111111"
        inclusion_prefixes = ["manuals/"]
      }
      faq = {
        bucket_arn              = "arn:aws:s3:::alpha-dev-kb-docs-111111111111"
        bucket_owner_account_id = "111111111111"
        data_deletion_policy    = "DELETE"
        chunking                = { max_tokens = 512, overlap_percentage = 10 }
      }
    }
  }

  assert {
    condition     = length(aws_bedrockagent_data_source.this) == 2
    error_message = "Expected one data source per entry"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].name == "manuals" && aws_bedrockagent_data_source.this["faq"].name == "faq"
    error_message = "Data source name must be the map key"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].data_source_configuration[0].type == "S3"
    error_message = "data_source_configuration.type must be S3"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].data_source_configuration[0].s3_configuration[0].bucket_arn == "arn:aws:s3:::alpha-dev-kb-docs-111111111111"
    error_message = "bucket_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].data_source_configuration[0].s3_configuration[0].inclusion_prefixes == toset(["manuals/"])
    error_message = "inclusion_prefixes must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["faq"].data_source_configuration[0].s3_configuration[0].inclusion_prefixes == null
    error_message = "inclusion_prefixes must not be sent when empty"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["faq"].data_source_configuration[0].s3_configuration[0].bucket_owner_account_id == "111111111111" && aws_bedrockagent_data_source.this["manuals"].data_source_configuration[0].s3_configuration[0].bucket_owner_account_id == null
    error_message = "bucket_owner_account_id must follow the input"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].data_deletion_policy == "RETAIN"
    error_message = "data_deletion_policy must default to RETAIN"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["faq"].data_deletion_policy == "DELETE"
    error_message = "data_deletion_policy must follow the input"
  }
  assert {
    condition = (
      aws_bedrockagent_data_source.this["manuals"].vector_ingestion_configuration[0].chunking_configuration[0].chunking_strategy == "FIXED_SIZE" &&
      aws_bedrockagent_data_source.this["manuals"].vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration[0].max_tokens == 300 &&
      aws_bedrockagent_data_source.this["manuals"].vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration[0].overlap_percentage == 20
    )
    error_message = "chunking must default to FIXED_SIZE, 300 tokens, 20 percent overlap"
  }
  assert {
    condition = (
      aws_bedrockagent_data_source.this["faq"].vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration[0].max_tokens == 512 &&
      aws_bedrockagent_data_source.this["faq"].vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration[0].overlap_percentage == 10
    )
    error_message = "max_tokens and overlap_percentage must follow the input"
  }
  assert {
    condition     = length(aws_bedrockagent_data_source.this["manuals"].server_side_encryption_configuration) == 0
    error_message = "No server_side_encryption_configuration when kms_key_arn is null"
  }
}

run "chunking_none_omits_fixed_size" {
  command = plan

  variables {
    data_sources = {
      prechunked = {
        bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111"
        chunking   = { strategy = "NONE" }
      }
    }
  }

  assert {
    condition     = aws_bedrockagent_data_source.this["prechunked"].vector_ingestion_configuration[0].chunking_configuration[0].chunking_strategy == "NONE"
    error_message = "chunking_strategy must follow the input"
  }
  assert {
    condition     = length(aws_bedrockagent_data_source.this["prechunked"].vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration) == 0
    error_message = "fixed_size_chunking_configuration must not be sent when strategy is NONE"
  }
}

run "kms_key_on_data_sources" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111" }
    }
  }

  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].server_side_encryption_configuration[0].kms_key_arn == var.kms_key_arn
    error_message = "server_side_encryption_configuration.kms_key_arn must be kms_key_arn"
  }
}

run "tags_add_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-docs" })
    error_message = "tags must be the input plus Name"
  }
}

run "outputs" {
  command = apply

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111" }
    }
  }

  assert {
    condition     = output.knowledge_base_id == "KBID000001"
    error_message = "knowledge_base_id must be the knowledge base id"
  }
  assert {
    condition     = output.knowledge_base_arn == "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"
    error_message = "knowledge_base_arn must be the knowledge base ARN"
  }
  assert {
    condition     = length(output.data_source_ids) == 1 && output.data_source_ids["manuals"] == "DSID000001"
    error_message = "data_source_ids must map keys to data_source_id, not the composite id"
  }
  assert {
    condition     = aws_bedrockagent_data_source.this["manuals"].knowledge_base_id == "KBID000001"
    error_message = "Data sources must attach to this knowledge base"
  }
}
