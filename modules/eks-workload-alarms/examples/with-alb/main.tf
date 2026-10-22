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
  cluster_name   = "alpha-sit"
  namespace      = "alpha"
  workload_name  = "alpha-api"
  container_name = "api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-sit-alarms"]

  load_balancer = {
    alb_arn_suffix          = "app/alpha-sit/0123456789abcdef"
    target_group_arn_suffix = "targetgroup/alpha-api/0123456789abcdef"
  }
  restart_threshold = 2

  alarm_config = {
    alb = { latency_p95_threshold_ms = 1500 }
  }

  tags = {
    Project = "alpha"
  }
}

output "alarm_arns" {
  value = module.alarms.alarm_arns
}
