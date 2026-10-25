terraform {
  required_version = ">= 1.10"

  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.107, < 2.0"
    }
  }
}
