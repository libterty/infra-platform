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

# Call once per account and region, from the account baseline or one project's foundation stack.
module "glue_catalog_encryption" {
  source = "../.."

  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

output "catalog_id" {
  value = module.glue_catalog_encryption.catalog_id
}
