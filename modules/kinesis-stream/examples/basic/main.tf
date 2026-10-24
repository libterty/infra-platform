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

module "events" {
  source = "../.."

  name        = "alpha-dev-events"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  mode        = "PROVISIONED"
  shard_count = 1

  tags = {
    Project = "alpha"
  }
}

output "stream_arn" {
  value = module.events.arn
}
