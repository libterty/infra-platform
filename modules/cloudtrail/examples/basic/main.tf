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

module "trail" {
  source = "../.."

  name           = "alpha-dev-trail"
  s3_bucket_name = "alpha-dev-audit-logs"
  s3_key_prefix  = "cloudtrail"
  kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  cloudwatch_logs = {
    log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/alpha-dev:*"
    role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-cloudtrail-logs"
  }

  tags = {
    Project = "alpha"
  }
}

output "trail_arn" {
  value = module.trail.arn
}
