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

variable "origin_verify_header_value" {
  type        = string
  sensitive   = true
  description = "Pass with TF_VAR_origin_verify_header_value; never put it in tfvars."
}

# SPA on S3 as the default behavior and an API Gateway HTTP API under /api/*. The Lambda behind the API compares
# X-Origin-Verify with the value in Secrets Manager, so calls to the public execute-api URL that skip CloudFront
# and its WAF get a 403.
module "web" {
  source = "../.."

  name            = "alpha-dev-web"
  aliases         = ["app.dev.example.com"]
  certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  web_acl_arn     = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/alpha-dev-edge/11111111-2222-3333-4444-555555555555"

  origins = {
    site = {
      type        = "s3"
      domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com"
    }
    api = {
      type        = "custom"
      domain_name = "abcde12345.execute-api.ap-northeast-1.amazonaws.com"
    }
  }

  default_behavior = {
    origin = "site"
  }

  ordered_behaviors = [
    {
      path_pattern          = "/api/*"
      origin                = "api"
      allowed_methods       = "all"
      cache_policy          = "Managed-CachingDisabled"
      origin_request_policy = "Managed-AllViewerExceptHostHeader"
    },
  ]

  origin_verify = {
    origin      = "api"
    header_name = "X-Origin-Verify"
  }
  origin_verify_header_value = var.origin_verify_header_value

  default_root_object = "index.html"
  spa_fallback        = true

  tags = {
    Project = "alpha"
  }
}

output "distribution_arn" {
  value = module.web.arn
}

output "hosted_zone_id" {
  value = module.web.hosted_zone_id
}
