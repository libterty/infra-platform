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

# Single page app on S3. The bucket policy that lets this distribution read the bucket is set by s3-bucket
# (cloudfront_distribution_arns = [module.web.arn]).
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
  }

  default_behavior = {
    origin = "site"
  }

  default_root_object = "index.html"
  spa_fallback        = true

  tags = {
    Project = "alpha"
  }
}

output "distribution_arn" {
  value = module.web.arn
}

output "domain_name" {
  value = module.web.domain_name
}
