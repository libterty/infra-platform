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

module "peering" {
  source = "../.."

  name          = "alpha-dev-to-partner"
  vpc_id        = "vpc-0123456789abcdef0"
  vpc_cidr      = "10.10.0.0/16"
  peer_vpc_id   = "vpc-0fedcba9876543210"
  peer_owner_id = "444444444444"

  route_table_ids = ["rtb-0123456789abcdef0", "rtb-0fedcba9876543210"]
  peer_cidrs      = ["10.250.0.0/16"]

  tags = {
    Project = "alpha"
  }
}

output "peering_connection_id" {
  value = module.peering.peering_connection_id
}
