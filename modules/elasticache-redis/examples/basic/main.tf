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

module "redis" {
  source = "../.."

  name           = "alpha-dev-rate-limit"
  engine_version = "7.1"
  node_type      = "cache.r7g.large"

  subnet_ids         = ["subnet-0aaa1111", "subnet-0bbb2222"]
  security_group_ids = ["sg-0123456789abcdef0"]

  num_node_groups         = 2
  replicas_per_node_group = 1

  parameters = {
    "maxmemory-policy" = "volatile-lru"
  }

  autoscaling = {
    min_shards = 2
    max_shards = 6
  }

  alarm_config = {
    memory_percent      = 80
    evictions_threshold = 1000
  }
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  tags = {
    Project = "alpha"
  }
}

output "configuration_endpoint" {
  value = module.redis.configuration_endpoint
}
