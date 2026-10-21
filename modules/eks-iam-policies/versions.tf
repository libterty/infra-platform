terraform {
  required_version = ">= 1.10"

  # This module creates no resource and uses no provider. Terraform still needs aws declared here: without
  # it, "terraform test" fails with "unknown provider registry.terraform.io/hashicorp/aws" on the
  # mock_provider "aws" that scripts/validate.sh (S1) requires in every test file.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}
