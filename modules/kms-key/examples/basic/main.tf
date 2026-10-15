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

module "key" {
  source = "../.."

  name        = "alpha-dev"
  description = "alpha dev shared key"

  service_principals = {
    "logs.ap-northeast-1.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:ap-northeast-1:111111111111:log-group:*"]
      }]
    }
    "cloudwatch.amazonaws.com" = {}
  }

  tags = {
    Project = "alpha"
  }
}

output "key_arn" {
  value = module.key.key_arn
}
