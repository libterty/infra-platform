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

module "cluster" {
  source = "../.."

  name                      = "alpha-dev"
  service_connect_namespace = "alpha-dev.local"

  tags = {
    Project = "alpha"
  }
}

output "cluster_arn" {
  value = module.cluster.cluster_arn
}
