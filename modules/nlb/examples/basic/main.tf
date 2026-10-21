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

module "nlb" {
  source = "../.."

  name               = "alpha-dev"
  subnet_ids         = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  security_group_ids = ["sg-0123456789abcdef0"]
  vpc_id             = "vpc-0123456789abcdef0"
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  target_groups = {
    # Plain TCP service: one target group, AWS default DNS failover.
    web = { port = 8080 }

    # Weighted cut-over: both target groups must have DNS failover off (see README).
    new = { port = 8443, dns_failover = "off" }
    old = { port = 8443, dns_failover = "off" }
  }

  listeners = {
    web = {
      port    = 80
      targets = { web = { target_group = "web", weight = 1 } }
    }

    canary = {
      port            = 443
      protocol        = "TLS"
      certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
      targets = {
        new = { target_group = "new", weight = 10 }
        old = { target_group = "old", weight = 90 }
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "nlb_arn_suffix" {
  value = module.nlb.nlb_arn_suffix
}

output "listener_arns" {
  value = module.nlb.listener_arns
}

output "target_group_arns" {
  value = module.nlb.target_group_arns
}
