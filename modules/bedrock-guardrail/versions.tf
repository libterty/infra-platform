terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_bedrock_guardrail tier_config and cross_region_config were only checked against 6.69.0.
      version = ">= 6.69, < 7.0"
    }
  }
}
