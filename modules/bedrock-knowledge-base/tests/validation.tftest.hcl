mock_provider "aws" {}

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
      cluster_arn            = "arn:aws:rds:us-west-2:222222222222:cluster:beta-prod-db"
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
      faq_v2-zh = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111" }
    }
  }
}

run "data_source_key_rejected" {
  command = plan

  variables {
    data_sources = {
      "faq-" = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111" }
    }
  }

  expect_failures = [var.data_sources]
}

run "bucket_arn_bucket_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111" }
    }
  }
}

run "bucket_arn_object_path_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111/manuals" }
    }
  }

  expect_failures = [var.data_sources]
}

run "data_deletion_policy_delete_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", data_deletion_policy = "DELETE" }
    }
  }
}

run "data_deletion_policy_purge_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", data_deletion_policy = "PURGE" }
    }
  }

  expect_failures = [var.data_sources]
}

run "inclusion_prefix_relative_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", inclusion_prefixes = ["manuals/"] }
    }
  }
}

run "inclusion_prefix_leading_slash_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", inclusion_prefixes = ["/manuals/"] }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_strategy_none_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { strategy = "NONE" } }
    }
  }
}

run "chunking_strategy_semantic_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { strategy = "SEMANTIC" } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_max_tokens_one_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { max_tokens = 1 } }
    }
  }
}

run "chunking_max_tokens_zero_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { max_tokens = 0 } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_overlap_one_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { overlap_percentage = 1 } }
    }
  }
}

run "chunking_overlap_ninety_nine_accepted" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { overlap_percentage = 99 } }
    }
  }
}

run "chunking_overlap_zero_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { overlap_percentage = 0 } }
    }
  }

  expect_failures = [var.data_sources]
}

run "chunking_overlap_hundred_rejected" {
  command = plan

  variables {
    data_sources = {
      manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-docs-111111111111", chunking = { overlap_percentage = 100 } }
    }
  }

  expect_failures = [var.data_sources]
}
