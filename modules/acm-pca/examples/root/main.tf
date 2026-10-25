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

module "device_root_ca" {
  source = "../.."

  type = "ROOT"
  subject = {
    common_name  = "alpha-dev-device-root"
    organization = "Example"
    country      = "JP"
  }

  tags = {
    Project = "alpha"
  }
}

output "ca_arn" {
  value = module.device_root_ca.ca_arn
}

output "ca_certificate_pem" {
  value = module.device_root_ca.ca_certificate_pem
}
