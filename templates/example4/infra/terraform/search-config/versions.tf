terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.6.0, < 3.0"
    }
  }

  backend "s3" {}
}
