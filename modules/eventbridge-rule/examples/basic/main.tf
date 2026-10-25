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

module "model_approved" {
  source = "../.."

  name = "alpha-dev-model-approved"

  event_pattern = {
    source        = ["aws.sagemaker"]
    "detail-type" = ["SageMaker Model Package State Change"]
    detail = {
      ModelPackageGroupName = ["alpha-dev-models"]
      ModelApprovalStatus   = ["Approved"]
    }
  }

  targets = {
    queue = {
      arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
      retry = {
        maximum_event_age_seconds = 3600
        maximum_retry_attempts    = 10
      }
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "rule_arn" {
  value = module.model_approved.rule_arn
}
