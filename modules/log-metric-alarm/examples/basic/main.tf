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

module "log_alarms" {
  source = "../.."

  name_prefix    = "alpha-dev-api"
  log_group_name = "/ecs/alpha-dev-api"
  namespace      = "Alpha/dev"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  alarms = {
    persistence_write_failed = {
      pattern     = "{ $.event = \"persistence_write_failed\" }"
      metric_name = "PersistenceWriteFailed"
      description = "Audit rows failed to reach the database. Check RDS Proxy and database health first."
    }
    rate_limit_fail_open = {
      pattern     = "{ $.event = \"rate_limit_fail_open\" }"
      metric_name = "RateLimitFailOpen"
      description = "The rate limiter failed open. Check the Redis endpoint."
      period      = 300
      threshold   = 60
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "alarm_names" {
  value = module.log_alarms.alarm_names
}
