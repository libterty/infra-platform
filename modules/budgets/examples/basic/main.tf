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

locals {
  alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
}

module "budgets" {
  source = "../.."

  budgets = {
    alpha-dev-monthly = {
      limit_amount = 100
      notifications = [
        for n in [["ACTUAL", 80], ["ACTUAL", 100], ["FORECASTED", 100]] : {
          type           = n[0]
          threshold      = n[1]
          sns_topic_arns = [local.alarm_topic_arn]
          emails         = ["ops@example.com"]
        }
      ]
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "budget_arns" {
  value = module.budgets.budget_arns
}
