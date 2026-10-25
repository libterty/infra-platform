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

module "retrain" {
  source = "../.."

  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  group_name  = "alpha-dev-ml"

  schedules = {
    alpha-dev-retrain = {
      expression              = "cron(0 3 ? * MON *)"
      state                   = "DISABLED"
      flexible_window_minutes = 60
      target = {
        arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
        role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        sagemaker_pipeline_parameters = {
          InputPrefix = "s3://alpha-dev-ml-artifacts/datasets/"
        }
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "schedule_arns" {
  value = module.retrain.schedule_arns
}
