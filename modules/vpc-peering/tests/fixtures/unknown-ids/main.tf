# Test fixture: route table IDs are not known until apply, as when the module is
# called in the same configuration that creates the route tables.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = "vpc-0123456789abcdef0"
}

module "peering" {
  source = "../../.."

  name          = "alpha-dev-to-partner"
  vpc_id        = "vpc-0123456789abcdef0"
  vpc_cidr      = "10.10.0.0/16"
  peer_vpc_id   = "vpc-0fedcba9876543210"
  peer_owner_id = "444444444444"

  route_table_ids = aws_route_table.private[*].id
  peer_cidrs      = ["10.250.0.0/16", "10.251.0.0/16"]
}
