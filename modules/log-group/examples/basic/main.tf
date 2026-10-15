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

module "log_group" {
  source = "../.."

  name           = "/alpha/dev/worker"
  retention_days = 90

  subscription = {
    destination_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-logs"
    filter_pattern  = "ERROR"
    role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-cwl-to-firehose"
  }

  tags = {
    Project = "alpha"
  }
}

output "log_group_name" {
  value = module.log_group.name
}
