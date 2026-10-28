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

module "api" {
  source = "../.."

  name = "alpha-dev-api"

  jwt_authorizers = {
    cognito = {
      issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
      audience = ["1example23456789"]
    }
  }

  integrations = {
    items = {
      lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-items"
    }
  }

  routes = {
    "GET /api/items" = {
      integration = "items"
      authorizer  = "cognito"
      scopes      = ["alpha/items.read"]
    }
    "GET /api/health" = {
      integration = "items"
      public      = true
    }
  }

  throttling = {
    rate_limit  = 50
    burst_limit = 100
  }

  access_log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/apigateway/alpha-dev-api"

  # CloudFront uses the execute-api URL as its origin.
  disable_execute_api_endpoint = false

  tags = {
    Project = "alpha"
  }
}

output "api_endpoint" {
  value = module.api.api_endpoint
}
