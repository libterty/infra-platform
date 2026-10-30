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

# Builds the api container image inside CodePipeline, so docker needs privileged mode.
module "api_build" {
  source = "../.."

  name               = "alpha-dev-api-build"
  description        = "Build and push the alpha api image"
  service_role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-api-build"
  encryption_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  buildspec          = "ci/api/buildspec.yml"

  environment = {
    privileged_mode = true
  }

  environment_variables = {
    AWS_ACCOUNT_ID = { value = "111111111111" }
    IMAGE_REPO     = { value = "alpha/api" }
    NPM_TOKEN      = { value = "/alpha/dev/npm-token", type = "PARAMETER_STORE" }
  }

  log_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-0a1b-0a1b-0a1b-0a1b2c3d4e5f"

  tags = {
    Project = "alpha"
  }
}

output "project_name" {
  value = module.api_build.name
}
