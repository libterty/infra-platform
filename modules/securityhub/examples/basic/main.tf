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

module "securityhub" {
  source = "../.."

  standards = ["fsbp", "cis"]
}

output "standards_subscription_arns" {
  value = module.securityhub.standards_subscription_arns
}
