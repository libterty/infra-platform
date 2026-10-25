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

module "cameras" {
  source = "../.."

  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  streams = {
    alpha-dev-cam-01 = {
      retention_hours = 24
      device_name     = "alpha-dev-core-01"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "stream_arns" {
  value = module.cameras.stream_arns
}
