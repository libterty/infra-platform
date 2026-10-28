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

# AWS managed key, no resource policy, no rotation.
module "signing_key" {
  source = "../.."

  name        = "alpha-dev/app-signing-public-key"
  description = "Public key that verifies the tokens the application issues. The value is written outside Terraform."
}

module "db_user" {
  source = "../.."

  name                    = "alpha-dev/db-user"
  description             = "Database user of alpha-dev as JSON with username and password. The value is written outside Terraform."
  kms_key_arn             = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  recovery_window_in_days = 30

  policy_statements = [{
    sid        = "DenyOtherAccounts"
    effect     = "Deny"
    principals = { type = "AWS", identifiers = ["*"] }
    actions    = ["secretsmanager:*"]
    conditions = [
      { test = "StringNotEquals", variable = "aws:PrincipalAccount", values = ["111111111111"] },
    ]
  }]

  rotation = {
    lambda_arn               = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-db-rotate"
    automatically_after_days = 30
    duration                 = "3h"
  }

  tags = {
    Project = "alpha"
  }
}

output "db_user_secret_arn" {
  value = module.db_user.arn
}
