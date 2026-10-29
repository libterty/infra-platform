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

module "guardduty" {
  source = "../.."

  tags = {
    Project = "alpha"
  }
}

output "detector_id" {
  value = module.guardduty.detector_id
}
