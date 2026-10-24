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

# Mutual TLS, split tunnel, one subnet, access to the data subnets only.
module "client_vpn" {
  source = "../.."

  name        = "alpha-dev-vpn"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  server_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  authentication = {
    mutual_tls_root_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/66666666-7777-8888-9999-000000000000"
  }

  client_cidr_block  = "10.250.0.0/22"
  vpc_id             = "vpc-0123456789abcdef0"
  vpc_cidr_blocks    = ["10.30.0.0/20"]
  subnet_ids         = ["subnet-0123456789abcdef0"]
  security_group_ids = ["sg-0123456789abcdef0"]

  authorization_rules = [
    { target_cidr = "10.30.8.0/22", description = "data subnets" },
  ]

  tags = {
    Project = "alpha"
  }
}

output "dns_name" {
  value = module.client_vpn.dns_name
}
