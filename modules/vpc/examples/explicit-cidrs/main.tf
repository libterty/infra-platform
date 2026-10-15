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

module "vpc" {
  source = "../.."

  name = "alpha-prod"
  cidr = "10.30.0.0/20"
  azs  = ["ap-northeast-1a", "ap-northeast-1c"]

  subnets = {
    public = {
      type  = "public"
      cidrs = { "ap-northeast-1a" = "10.30.0.0/24", "ap-northeast-1c" = "10.30.1.0/24" }
    }
    app = {
      type  = "private"
      cidrs = { "ap-northeast-1a" = "10.30.4.0/22", "ap-northeast-1c" = "10.30.8.0/22" }
    }
    data = {
      type  = "isolated"
      cidrs = { "ap-northeast-1a" = "10.30.12.0/24", "ap-northeast-1c" = "10.30.13.0/24" }
    }
  }

  nat_mode          = "per_az"
  gateway_endpoints = ["s3", "dynamodb"]

  flow_log = {
    destination_arn = "arn:aws:s3:::alpha-prod-flow-logs/vpc"
  }

  tags = {
    Project = "alpha"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
