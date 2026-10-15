terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# Before applying: enable the Data API on the cluster, then run the project migration that creates the
# vector extension, the table and the dedicated database user, and store that user in the secret below.
module "knowledge_base" {
  source = "../.."

  name                 = "alpha-dev-docs"
  description          = "Product manuals"
  role_arn             = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb"
  embedding_model_arn  = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
  embedding_dimensions = 1024

  aurora = {
    cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
    credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-bedrock-kb-user-AbCdEf"
    database_name          = "app"
    table_name             = "bedrock_integration.bedrock_kb"
  }

  data_sources = {
    manuals = {
      bucket_arn         = "arn:aws:s3:::alpha-dev-kb-docs-111111111111"
      inclusion_prefixes = ["manuals/"]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "knowledge_base_id" {
  value = module.knowledge_base.knowledge_base_id
}

output "data_source_ids" {
  value = module.knowledge_base.data_source_ids
}
