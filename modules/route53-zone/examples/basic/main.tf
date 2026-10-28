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

module "zone" {
  source = "../.."

  name    = "dev.example.com"
  comment = "alpha dev"

  tags = {
    Project = "alpha"
  }
}

output "zone_id" {
  value = module.zone.zone_id
}

output "name_servers" {
  value = module.zone.name_servers
}
