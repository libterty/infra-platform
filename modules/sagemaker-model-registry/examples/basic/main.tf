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

module "registry" {
  source = "../.."

  name        = "alpha-dev-detector"
  description = "Defect detector models"

  cross_account_read_principals = ["arn:aws:iam::222222222222:role/alpha-sit-inference"]

  tags = {
    Project = "alpha"
  }
}

output "model_package_group_arn" {
  value = module.registry.arn
}
