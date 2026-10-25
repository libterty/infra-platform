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

# First apply without subordinate_certificate, have the parent CA sign the csr output,
# then set subordinate_certificate and apply again to install it.
module "device_issuing_ca" {
  source = "../.."

  type       = "SUBORDINATE"
  usage_mode = "SHORT_LIVED_CERTIFICATE"
  subject = {
    common_name  = "alpha-dev-device-issuing"
    organization = "Example"
  }
}

output "csr" {
  value = module.device_issuing_ca.csr
}
