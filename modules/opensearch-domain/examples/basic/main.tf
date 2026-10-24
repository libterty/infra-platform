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

# The master secret is created outside Terraform's state of this module; its value is {"username": "...", "password": "..."}.
module "search" {
  source = "../.."

  name           = "alpha-dev-search"
  engine_version = "OpenSearch_2.19"

  hot = {
    instance_type  = "m7g.large.search"
    instance_count = 2
    ebs            = { volume_size = 20 }
  }
  dedicated_master = { instance_type = "m7g.large.search", count = 3 }
  warm             = { instance_type = "ultrawarm1.medium.search", count = 2 }
  cold_storage     = true

  availability_zone_count = 2
  subnet_ids              = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_ids      = ["sg-0123456789abcdef0"]

  kms_key_arn            = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-opensearch-master-AbCdEf"
  access_principal_arns  = ["arn:aws:iam::111111111111:role/alpha-dev-firehose"]

  log_retention_days = 90

  tags = {
    Project = "alpha"
  }
}

output "endpoint" {
  value = module.search.endpoint
}
