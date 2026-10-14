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

# 一般 RDS，不開 Proxy。subnet、SG、role、topic 的值在實際專案由 SSM 讀出，這裡用佔位值。
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

  # rds 與 aurora 要自己給連線數門檻（max_connections 取決於 instance class）
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
