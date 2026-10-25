terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # iotsitewise uses awscc (design K1).
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.107"
    }
  }

  backend "s3" {}
}
