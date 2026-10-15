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

module "endpoints" {
  source = "../.."

  name          = "alpha-prod"
  vpc_id        = "vpc-0123456789abcdef0"
  allowed_cidrs = ["10.30.0.0/20"]
  subnet_ids    = ["subnet-0aaa1111", "subnet-0bbb2222"]
  services      = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]

  tags = {
    Project = "alpha"
  }
}

output "endpoint_ids" {
  value = module.endpoints.endpoint_ids
}

output "security_group_id" {
  value = module.endpoints.security_group_id
}
