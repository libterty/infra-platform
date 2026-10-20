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

module "bastion" {
  source = "../.."

  name                  = "alpha-dev-bastion"
  subnet_id             = "subnet-0123456789abcdef0"
  security_group_ids    = ["sg-0123456789abcdef0"]
  instance_profile_name = "alpha-dev-bastion"

  tags = {
    Project = "alpha"
  }
}

output "instance_id" {
  value = module.bastion.instance_id
}
