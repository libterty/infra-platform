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

module "model_approved" {
  source = "../.."

  name        = "alpha-dev-model-approved"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  visibility_timeout_seconds = 300
  allowed_source_arns        = ["arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-model-approved"]

  tags = {
    Project = "alpha"
  }
}

output "queue_url" {
  value = module.model_approved.queue_url
}
