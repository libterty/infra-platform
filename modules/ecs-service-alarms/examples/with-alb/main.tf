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

module "alarms" {
  source = "../.."

  name           = "alpha-api"
  cluster_name   = "alpha-prod"
  service_name   = "alpha-api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-prod-alarms"]

  load_balancer = {
    alb_arn_suffix          = "app/alpha-prod/0123456789abcdef"
    target_group_arn_suffix = "targetgroup/alpha-api/0123456789abcdef"
  }
  max_capacity = 6

  alarm_config = {
    ecs = { cpu_threshold = 70 }
    alb = { latency_p95_threshold_ms = 1500 }
  }

  dashboard_name = "alpha-api"

  tags = {
    Project = "alpha"
  }
}

output "alarm_arns" {
  value = module.alarms.alarm_arns
}

output "dashboard_arn" {
  value = module.alarms.dashboard_arn
}
