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

module "access_analyzer" {
  source = "../.."

  name = "alpha-dev-account"

  archive_rules = {
    sit-account = [
      { criteria = "principal.AWS", eq = ["222222222222"] },
    ]
  }

  tags = {
    Project = "alpha"
  }
}

output "analyzer_arn" {
  value = module.access_analyzer.arn
}
