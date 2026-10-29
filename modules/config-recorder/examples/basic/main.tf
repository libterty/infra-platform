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

module "config" {
  source = "../.."

  name           = "default"
  role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-config-recorder"
  s3_bucket_name = "alpha-dev-audit-logs"
  s3_key_prefix  = "config"

  managed_rules = {
    S3_BUCKET_VERSIONING_ENABLED = {
      scope_resource_types = ["AWS::S3::Bucket"]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "recorder_name" {
  value = module.config.recorder_name
}
