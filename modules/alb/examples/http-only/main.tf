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

  name               = "alpha-dev"
  subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  security_group_ids = ["sg-0123456789abcdef0"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  deletion_protection = false
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "listener_arn" {
  value = module.alb.listener_arn
}
