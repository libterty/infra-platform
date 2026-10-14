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

module "alb" {
  source = "../.."

  name                        = "alpha-prod"
  subnet_ids                  = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  security_group_ids          = ["sg-0123456789abcdef0"]
  certificate_arn             = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  additional_certificate_arns = ["arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"]
  sns_topic_arns              = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-prod-alarms"]

  access_logs = {
    bucket = "alpha-prod-alb-logs"
    prefix = "alb"
  }
  web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-prod/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  tags = {
    Project = "alpha"
  }
}

output "alb_arn_suffix" {
  value = module.alb.alb_arn_suffix
}

output "listener_arn" {
  value = module.alb.listener_arn
}
