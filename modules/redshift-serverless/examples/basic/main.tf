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

module "warehouse" {
  source = "../.."

  name        = "alpha-dev-wh"
  db_name     = "analytics"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  iam_role_arns        = ["arn:aws:iam::111111111111:role/alpha-dev-redshift"]
  default_iam_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-redshift"

  base_capacity         = 4
  max_capacity          = 8
  usage_limit_rpu_hours = 100

  subnet_ids         = ["subnet-0a1b2c3d", "subnet-1a2b3c4d", "subnet-2a3b4c5d"]
  security_group_ids = ["sg-0a1b2c3d4e5f60718"]

  tags = {
    Project = "alpha"
  }
}

output "endpoint_address" {
  value = module.warehouse.endpoint_address
}

output "admin_secret_arn" {
  value = module.warehouse.admin_secret_arn
}
