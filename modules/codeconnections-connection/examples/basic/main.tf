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

module "github" {
  source = "../.."

  name = "alpha-dev-github"

  tags = {
    Project = "alpha"
  }
}

output "connection_arn" {
  value = module.github.arn
}

output "connection_status" {
  value = module.github.status
}
