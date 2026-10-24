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

# VPN Gateway attached to the VPC, static routing to one on-premises network.
module "vpn" {
  source = "../.."

  name        = "alpha-dev-onprem"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  vpc_id      = "vpc-0123456789abcdef0"
  vpn_gateway = {}

  customer_gateway = {
    ip_address = "198.51.100.10"
  }

  routing = {
    static_routes_only = true
    static_routes      = ["192.168.10.0/24"]
  }

  propagate_route_table_ids = ["rtb-0123456789abcdef0"]

  tags = {
    Project = "alpha"
  }
}

output "tunnel_addresses" {
  value = module.vpn.tunnel_addresses
}

output "preshared_key_secret_arn" {
  value = module.vpn.preshared_key_secret_arn
}
