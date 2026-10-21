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

module "alb" {
  source = "../.."

  name                        = "alpha-prod"
  subnet_ids                  = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  security_group_ids          = ["sg-0123456789abcdef0"]
  certificate_arn             = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  additional_certificate_arns = ["arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"]
  sns_topic_arns              = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-prod-alarms"]

  web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-prod/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  tags = {
    Project = "alpha"
  }
}

# Access logs go through log-delivery; the bucket comes from s3-bucket with log_delivery = ["vended_logs"].
module "alb_access_logs" {
  source = "../../../log-delivery"

  name_prefix = "alpha-prod-alb"

  sources = {
    access = { resource_arn = module.alb.alb_arn, log_type = "ALB_ACCESS_LOGS" }
  }

  destinations = {
    archive = { type = "S3", resource_arn = "arn:aws:s3:::alpha-prod-access-logs" }
  }

  deliveries = {
    access = { source = "access", destination = "archive" }
  }
}

output "alb_arn_suffix" {
  value = module.alb.alb_arn_suffix
}

output "listener_arn" {
  value = module.alb.listener_arn
}
