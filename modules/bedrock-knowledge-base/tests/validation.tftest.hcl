mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "ap-northeast-1" }
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

run "name_100_chars_accepted" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
}

run "name_101_chars_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.name]
}

run "name_leading_hyphen_rejected" {
  command = plan

  variables {
    name = "-alpha"
  }

  expect_failures = [var.name]
}

run "role_arn_iam_role_accepted" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/alpha-kb"
  }
}

run "role_arn_not_a_role_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/alpha"
  }

  expect_failures = [var.role_arn]
}

run "embedding_model_foundation_model_accepted" {
  command = plan

  variables {
    embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
  }
}

run "embedding_model_inference_profile_rejected" {
  command = plan

  variables {
    embedding_model_arn = "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.amazon.titan-embed-text-v2:0"
  }

  expect_failures = [var.embedding_model_arn]
}

run "embedding_dimensions_one_accepted" {
  command = plan

  variables {
    embedding_dimensions = 1
  }
}

run "embedding_dimensions_zero_rejected" {
  command = plan

  variables {
    embedding_dimensions = 0
  }

  expect_failures = [var.embedding_dimensions]
}

run "embedding_dimensions_fraction_rejected" {
  command = plan

  variables {
    embedding_dimensions = 1.5
  }

  expect_failures = [var.embedding_dimensions]
}

run "cluster_arn_cluster_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:Beta-prod-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }
}

run "cluster_arn_db_instance_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:db:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

run "credentials_secret_arn_secret_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:kb-user-x1Y2z3"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }
}

run "credentials_secret_arn_not_secret_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/kb-user"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

run "database_name_lowercase_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app_1"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }
}

run "database_name_uppercase_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "App"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

run "table_name_single_part_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_kb"
    }
  }
}

run "table_name_two_parts_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "kb_schema.kb_table_2"
    }
  }
}

run "table_name_uppercase_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.Bedrock_KB"
    }
  }

  expect_failures = [var.aurora]
}

run "table_name_double_quotes_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "\"bedrock_integration\".\"bedrock_kb\""
    }
  }

  expect_failures = [var.aurora]
}

run "table_name_three_parts_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "app.bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

run "field_mapping_distinct_with_custom_accepted" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { primary_key_field = "id", custom_metadata_field = "custom_metadata" }
    }
  }
}

run "field_mapping_duplicate_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { vector_field = "id" }
    }
  }

  expect_failures = [var.aurora]
}

run "field_mapping_custom_duplicate_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { custom_metadata_field = "metadata" }
    }
  }

  expect_failures = [var.aurora]
}

run "field_mapping_hyphen_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { text_field = "chunk-text" }
    }
  }

  expect_failures = [var.aurora]
}

run "field_mapping_uppercase_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { metadata_field = "Metadata" }
    }
  }

  expect_failures = [var.aurora]
}

run "data_source_key_accepted" {
  command = plan

  variables {
    data_sources = {
      faq_v2-zh = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111" }
    }
  }
}

run "data_source_key_rejected" {
  command = plan

  variables {
    data_sources = {
      "faq-" = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111" }
    }
  }

  expect_failures = [var.data_sources]
}

run "bucket_arn_bucket_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111" }
    }
  }
}

run "bucket_arn_object_path_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111/manuals", bucket_owner_account_id = "111111111111" }
    }
  }

  expect_failures = [var.data_sources]
}

run "data_deletion_policy_delete_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", data_deletion_policy = "DELETE" }
    }
  }
}

run "data_deletion_policy_purge_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", data_deletion_policy = "PURGE" }
    }
  }

  expect_failures = [var.data_sources]
}

run "inclusion_prefix_relative_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", inclusion_prefixes = ["manuals/"] }
    }
  }
}

run "inclusion_prefix_leading_slash_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", inclusion_prefixes = ["/manuals/"] }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_strategy_none_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { strategy = "NONE" } }
    }
  }
}

run "chunking_strategy_semantic_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { strategy = "SEMANTIC" } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_max_tokens_one_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { max_tokens = 1 } }
    }
  }
}

run "chunking_max_tokens_zero_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { max_tokens = 0 } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_overlap_one_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { overlap_percentage = 1 } }
    }
  }
}

run "chunking_overlap_ninety_nine_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { overlap_percentage = 99 } }
    }
  }
}

run "chunking_overlap_zero_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { overlap_percentage = 0 } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_overlap_hundred_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "111111111111", chunking = { overlap_percentage = 100 } }
    }
  }

  expect_failures = [var.data_sources]
}

# role_arn path segments

run "role_arn_nested_path_accepted" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/bedrock/alpha-kb"
  }
}

run "role_arn_empty_path_segment_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role//alpha-kb"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_trailing_slash_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/"
  }

  expect_failures = [var.role_arn]
}

# embedding_model_arn tail

run "embedding_model_wildcard_rejected" {
  command = plan

  variables {
    embedding_model_arn = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-*"
  }

  expect_failures = [var.embedding_model_arn]
}

# credentials_secret_arn must be an exact secret ARN

run "credentials_secret_arn_wildcard_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-*"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

run "credentials_secret_arn_without_suffix_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-kb"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [var.aurora]
}

# cluster and secret must be in the current account and region

run "cluster_arn_other_account_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:222222222222:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [aws_bedrockagent_knowledge_base.this]
}

run "cluster_arn_other_region_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:us-west-2:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [aws_bedrockagent_knowledge_base.this]
}

run "credentials_secret_arn_other_account_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:222222222222:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [aws_bedrockagent_knowledge_base.this]
}

run "credentials_secret_arn_other_region_rejected" {
  command = plan

  variables {
    aurora = {
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:us-west-2:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
    }
  }

  expect_failures = [aws_bedrockagent_knowledge_base.this]
}

# bucket_owner_account_id and allowed_account_ids

run "bucket_owner_not_12_digits_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", bucket_owner_account_id = "11111111111" }
    }
  }

  expect_failures = [var.data_sources]
}

run "bucket_owner_other_account_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-222222222222", bucket_owner_account_id = "222222222222" }
    }
  }

  expect_failures = [aws_bedrockagent_data_source.this]
}

run "bucket_owner_other_account_allowed_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-222222222222", bucket_owner_account_id = "222222222222" }
    }
  }
}

run "bucket_owner_not_in_allowed_list_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["333333333333"]
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-222222222222", bucket_owner_account_id = "222222222222" }
    }
  }

  expect_failures = [aws_bedrockagent_data_source.this]
}

run "allowed_account_ids_valid_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222", "333333333333"]
  }
}

run "allowed_account_ids_not_12_digits_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["2222"]
  }

  expect_failures = [var.allowed_account_ids]
}

# kms_key_arn

run "kms_key_arn_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-4e5f-6789-abcd-ef0123456789"
  }
}

run "kms_key_arn_multi_region_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
  }
}

run "kms_key_arn_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_wildcard_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/*"
  }

  expect_failures = [var.kms_key_arn]
}
