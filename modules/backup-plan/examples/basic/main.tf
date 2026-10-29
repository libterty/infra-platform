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

module "backup_plan" {
  source = "../.."

  name       = "alpha-dev-daily"
  vault_name = "alpha-dev-backup"
  role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-backup"

  rules = {
    daily = {
      schedule          = "cron(0 18 * * ? *)"
      delete_after_days = 35
    }
  }

  selection_tags = {
    backup = "daily"
  }

  tags = {
    Project = "alpha"
  }
}

output "plan_arn" {
  value = module.backup_plan.plan_arn
}
