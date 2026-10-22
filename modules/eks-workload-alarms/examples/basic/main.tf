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

  name           = "alpha-worker"
  cluster_name   = "alpha-dev"
  namespace      = "alpha"
  workload_name  = "alpha-worker"
  container_name = "worker"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

output "alarm_names" {
  value = module.alarms.alarm_names
}
