terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # iot-device-defender and iot-job-template use awscc (design K1).
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.107"
    }
  }

  backend "s3" {}
}
