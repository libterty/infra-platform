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

module "publish" {
  source = "../.."

  ssm_prefix = "/alpha/dev"
  stack      = "network"

  strings = {
    vpc_id = "vpc-0123456789abcdef0"
  }

  lists = {
    subnet_ids_private = ["subnet-aaa", "subnet-bbb"]
  }
}

output "names" {
  value = module.publish.names
}
