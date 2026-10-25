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

module "firmware_signing" {
  source = "../.."

  name            = "alpha_dev_firmware"
  platform_id     = "AmazonFreeRTOS-Default"
  certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"

  signing_parameters = {
    certname = "ota_signer_pub.pem"
  }

  start_job_principals = ["arn:aws:iam::111111111111:role/alpha-dev-ci"]

  tags = {
    Project = "alpha"
  }
}

output "profile_name" {
  value = module.firmware_signing.profile_name
}
