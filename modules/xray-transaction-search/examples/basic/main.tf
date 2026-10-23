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

# Call once per account and region, from the account baseline, not from project stacks.
module "xray_transaction_search" {
  source = "../.."

  indexing_percentage = 1
}

output "spans_log_group_name" {
  value = module.xray_transaction_search.spans_log_group_name
}
