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

module "athena" {
  source = "../.."

  name                = "alpha-dev"
  results_bucket_name = "alpha-dev-athena-results"
  kms_key_arn         = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  bytes_scanned_cutoff_per_query = 21474836480

  named_queries = {
    latest-events = {
      database    = "alpha_dev_curated"
      description = "最新 10 筆事件"
      query       = "SELECT * FROM events ORDER BY event_time DESC LIMIT 10"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "workgroup_name" {
  value = module.athena.name
}
