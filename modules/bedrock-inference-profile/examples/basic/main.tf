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

module "inference_profile" {
  source = "../.."

  name_prefix = "alpha-dev"

  profiles = {
    chat = {
      copy_from   = "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-3-5-sonnet-20240620-v1:0"
      description = "Chat traffic for alpha-dev"
    }
    embedding = {
      copy_from = "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  tags = {
    Project = "alpha"
  }
}

output "arns" {
  value = module.inference_profile.arns
}

output "ids" {
  value = module.inference_profile.ids
}
