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

# ARNs and IDs are placeholders for values a real stack reads from SSM.
module "worker" {
  source = "../.."

  name        = "alpha-worker"
  cluster_arn = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
  image       = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-worker:1.0.0"

  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
  task_role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-alpha-worker-task"

  network = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
    security_group_ids = ["sg-0cccccccccccccccc"]
  }

  environment = { LOG_LEVEL = "info" }
  secrets     = { API_KEY = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha/api-AbCdEf" }

  tags = { Project = "alpha" }
}

output "service_name" {
  value = module.worker.service_name
}
