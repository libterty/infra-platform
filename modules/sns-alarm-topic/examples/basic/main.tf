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

module "alarm_topic" {
  source = "../.."

  name                = "alpha-dev-alarms"
  email_subscriptions = ["ops@example.com"]
  service_publishers  = ["budgets.amazonaws.com", "events.amazonaws.com"]

  tags = {
    Project = "alpha"
  }
}

output "topic_arn" {
  value = module.alarm_topic.topic_arn
}
