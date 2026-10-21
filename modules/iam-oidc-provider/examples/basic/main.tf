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

module "oidc" {
  source = "../.."

  # In a real stack this is the oidc_issuer_url output of eks-cluster.
  issuer_url = "https://oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"

  tags = {
    Project = "alpha"
    Env     = "dev"
  }
}

output "arn" {
  value = module.oidc.arn
}

output "issuer" {
  value = module.oidc.issuer
}
