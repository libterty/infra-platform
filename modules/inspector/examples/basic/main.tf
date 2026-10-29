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

module "inspector" {
  source = "../.."

  resource_types = ["EC2", "ECR", "LAMBDA"]
}

output "enabled_resource_types" {
  value = module.inspector.enabled_resource_types
}
