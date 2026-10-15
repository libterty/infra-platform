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

module "ecs_execution" {
  source = "../.."

  name        = "alpha-dev-ecs-execution"
  description = "ECS task execution role"

  trust = {
    service_principals = ["ecs-tasks.amazonaws.com"]
    source_account     = "111111111111"
  }

  inline_policies = {
    ecr-pull = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
          Resource = [
            "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api",
          ]
        },
      ]
    })
  }
}

output "arn" {
  value = module.ecs_execution.arn
}
