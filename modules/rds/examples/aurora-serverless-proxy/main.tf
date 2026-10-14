terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# Roles come from the iam-base stack; ARNs here are placeholders.
module "db" {
  source = "../.."

  name           = "alpha-prod-db"
  deployment     = "aurora_serverless"
  engine_version = "16.4"
  database_name  = "app"

  serverless = {
    min_capacity = 0.5
    max_capacity = 8
    reader_count = 1
  }

  subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_ids = ["sg-0123456789abcdef0"]

  proxy = {
    security_group_ids = ["sg-0fedcba9876543210"]
    role_arn           = "arn:aws:iam::111111111111:role/alpha-prod-rds-proxy"
  }

  monitoring     = { role_arn = "arn:aws:iam::111111111111:role/alpha-prod-rds-monitoring" }
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-prod-alarms"]

  tags = {
    Project = "alpha"
  }
}

output "app_endpoint" {
  value = module.db.app_endpoint
}

output "app_reader_endpoint" {
  value = module.db.app_reader_endpoint
}
