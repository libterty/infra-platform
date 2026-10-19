locals {
  interface_endpoints = {
    vpc_id = local.vpc_id
    # A VPC can have secondary CIDRs; every associated one must reach the endpoints.
    allowed_cidrs = local.create_vpc ? [local.vpc_cidr] : [for a in data.aws_vpc.existing[0].cidr_block_associations : a.cidr_block if a.state == "associated"]
    subnet_ids    = try(local.subnet_ids[var.interface_endpoints.subnet_tier], [])
    services      = var.interface_endpoints.services
  }
}

module "vpce" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/vpc-interface-endpoints/aws"
  version = "~> 0.1.0"

  name          = local.name_prefix
  vpc_id        = local.interface_endpoints.vpc_id
  allowed_cidrs = local.interface_endpoints.allowed_cidrs
  subnet_ids    = local.interface_endpoints.subnet_ids
  services      = local.interface_endpoints.services
}
