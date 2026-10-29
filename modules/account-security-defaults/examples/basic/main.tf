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

# Primary region: account-wide settings plus the regional defaults.
module "defaults" {
  source = "../.."

  ebs_default_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# Another region: only the regional defaults; the account-wide settings exist once.
module "defaults_us_east_1" {
  source = "../.."

  region                 = "us-east-1"
  s3_public_access_block = false
  password_policy        = null
}
