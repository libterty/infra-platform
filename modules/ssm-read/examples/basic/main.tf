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

module "in" {
  source = "../.."

  ssm_prefix = "/alpha/dev"

  strings = {
    vpc_id   = "network/vpc_id"
    database = "data/database"
  }

  lists = {
    subnet_ids_app = "network/subnet_ids_app"
  }
}

output "vpc_id" {
  value = module.in.strings["vpc_id"]
}

output "database" {
  value = jsondecode(module.in.strings["database"])
}

output "subnet_ids_app" {
  value = module.in.lists["subnet_ids_app"]
}
