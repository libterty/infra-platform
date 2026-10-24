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

module "access_logs" {
  source = "../.."

  name            = "alpha-dev-access-logs"
  log_delivery    = ["vended_logs"]
  expiration_days = 14

  tags = {
    Project = "alpha"
  }
}

module "flow_logs" {
  source = "../.."

  name         = "alpha-dev-flow-logs"
  log_delivery = ["vpc_flow_logs"]
  kms_key_arn  = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

module "raw" {
  source = "../.."

  name            = "alpha-dev-raw"
  kms_key_arn     = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  expiration_days = 365
  eventbridge     = true

  transitions = [
    { days = 30, storage_class = "STANDARD_IA" },
    { days = 90, storage_class = "GLACIER_IR" },
  ]
}

output "access_logs_bucket" {
  value = module.access_logs.bucket_name
}
