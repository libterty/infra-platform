terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.69, < 7.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

locals {
  alb_arn            = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev-web/50dc6c495c0c9188"
  assets_bucket_arn  = "arn:aws:s3:::alpha-dev-assets"
  access_log_group   = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/alpha-dev/access"
  archive_bucket_arn = "arn:aws:s3:::alpha-dev-log-archive"
}

module "access_logs" {
  source = "../.."

  name_prefix = "alpha-dev"

  sources = {
    web-access = {
      resource_arn = local.alb_arn
      log_type     = "ALB_ACCESS_LOGS"
    }
    assets-access = {
      resource_arn = local.assets_bucket_arn
      log_type     = "S3_SERVER_ACCESS_LOGS"
    }
  }

  destinations = {
    access = {
      type         = "CWL"
      resource_arn = local.access_log_group
    }
    archive = {
      type         = "S3"
      resource_arn = local.archive_bucket_arn
    }
  }

  # ALB access logs go to both CloudWatch Logs and the archive bucket; S3 access logs only to the archive.
  deliveries = {
    web-access         = { source = "web-access", destination = "access" }
    web-access-archive = { source = "web-access", destination = "archive" }
    assets-access      = { source = "assets-access", destination = "archive" }
  }

  tags = {
    Project = "alpha"
  }
}

output "delivery_ids" {
  value = module.access_logs.delivery_ids
}
