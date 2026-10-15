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

module "proxy_secret_access" {
  source = "../.."

  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-db-proxy"

  policies = {
    read-master-secret = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-x"
      }]
    })
  }
}

output "policy_names" {
  value = module.proxy_secret_access.policy_names
}
