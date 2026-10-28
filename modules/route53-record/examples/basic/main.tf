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

module "records" {
  source = "../.."

  zone_id = "Z0123456789ABCDEFGHIJ"

  records = {
    app = {
      name = "app.dev.example.com"
      type = "A"
      alias = {
        name    = "d111111abcdef8.cloudfront.net"
        zone_id = "Z2FDTNDATAQYW2" # CloudFront's fixed hosted zone ID
      }
    }
    www = {
      name   = "www.dev.example.com"
      type   = "CNAME"
      ttl    = 300
      values = ["app.dev.example.com"]
    }
    spf = {
      name   = "dev.example.com"
      type   = "TXT"
      ttl    = 300
      values = ["v=spf1 -all"]
    }
  }
}

output "fqdns" {
  value = module.records.fqdns
}
