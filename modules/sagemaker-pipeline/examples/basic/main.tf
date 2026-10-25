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

module "train" {
  source = "../.."

  name               = "alpha-dev-train"
  definition         = file("${path.module}/pipeline.json")
  role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-sagemaker-pipeline"
  description        = "Weekly retraining"
  max_parallel_steps = 2

  tags = {
    Project = "alpha"
  }
}

output "pipeline_arn" {
  value = module.train.pipeline_arn
}
