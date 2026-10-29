terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# Apply with credentials of the organization's management account.
provider "aws" {
  region = "ap-northeast-1"
}

module "delegated_admin" {
  source = "../.."

  delegated_admin_account_id = "333333333333"
  services                   = ["guardduty", "securityhub", "inspector", "config", "access-analyzer"]
  regions                    = ["ap-northeast-1", "us-east-1"]
}

output "trusted_service_principals" {
  value = module.delegated_admin.trusted_service_principals
}
