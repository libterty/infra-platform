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

# IDs and ARNs are placeholders for values a real stack reads from SSM.
module "db" {
  source = "../.."

  name           = "alpha-dev-db"
  deployment     = "rds"
  engine_version = "16.4"
  database_name  = "app"

  rds = {
    instance_class = "db.t4g.small"
  }

  subnet_ids         = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_ids = ["sg-0123456789abcdef0"]

  # rds and aurora need an explicit threshold because max_connections depends on the instance class.
  alarm_config   = { connections_threshold = 80 }
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]

  tags = {
    Project = "alpha"
  }
}

output "app_endpoint" {
  value = module.db.app_endpoint
}

output "master_user_secret_arn" {
  value = module.db.master_user_secret_arn
}
