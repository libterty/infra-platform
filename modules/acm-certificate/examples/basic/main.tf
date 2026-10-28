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

# Regional certificate for an ALB in the provider region.
module "alb_certificate" {
  source = "../.."

  domain_name               = "api.dev.example.com"
  subject_alternative_names = ["origin-api.dev.example.com"]
  zone_id                   = "Z0123456789ABCDEFGHIJ"
}

# CloudFront only accepts certificates from us-east-1.
module "cdn_certificate" {
  source = "../.."

  domain_name               = "dev.example.com"
  subject_alternative_names = ["*.dev.example.com"]
  zone_id                   = "Z0123456789ABCDEFGHIJ"
  region                    = "us-east-1"

  tags = {
    Project = "alpha"
  }
}

output "alb_certificate_arn" {
  value = module.alb_certificate.certificate_arn
}

output "cdn_certificate_arn" {
  value = module.cdn_certificate.certificate_arn
}
