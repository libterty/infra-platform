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

module "xray" {
  source = "../.."

  name_prefix = "alpha-dev"

  sampling_rules = {
    # Drop health checks, then sample 5 percent of API traffic.
    health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" }
    api    = { priority = 200, fixed_rate = 0.05, reservoir_size = 1, service_name = "alpha-dev-api" }
  }

  groups = {
    errors = { filter_expression = "fault = true OR error = true" }
    slow   = { filter_expression = "responsetime > 3" }
  }

  tags = {
    Project = "alpha"
  }
}

output "sampling_rule_arns" {
  value = module.xray.sampling_rule_arns
}

output "group_arns" {
  value = module.xray.group_arns
}
