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

module "ecr" {
  source = "../.."

  name = "alpha-dev-api"
}

output "repository_url" {
  value = module.ecr.repository_url
}
