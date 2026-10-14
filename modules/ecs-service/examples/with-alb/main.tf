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

# listener_arn mode with CPU and request-count target tracking.
module "api" {
  source = "../.."

  name           = "alpha-api"
  cluster_arn    = "arn:aws:ecs:ap-northeast-1:111111111111:cluster/alpha-dev"
  image          = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-api:1.0.0"
  container_port = 8000

  execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-ecs-execution"
  task_role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-alpha-api-task"

  network = {
    subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
    security_group_ids = ["sg-0cccccccccccccccc"]
  }

  load_balancer = {
    listener_arn   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-alb/0123456789abcdef/fedcba9876543210"
    vpc_id         = "vpc-0123456789abcdef0"
    priority       = 100
    path_patterns  = ["/api/*"]
    alb_arn_suffix = "app/alpha-alb/0123456789abcdef"
  }

  autoscaling = {
    min_capacity    = 2
    max_capacity    = 8
    target_tracking = { requests_per_target = 300 }
  }

  tags = { Project = "alpha" }
}

output "target_group_arn_suffix" {
  value = module.api.target_group_arn_suffix
}
