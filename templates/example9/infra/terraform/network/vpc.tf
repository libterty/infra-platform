locals {
  # Slots are counted in units of each tier's own subnet size. With a /16 and up to three AZs: public /24 at
  # 10.x.0.0-2.255 (NAT gateways only), app /20 at 10.x.16.0-63.255 (ECS tasks and the internal ALB).
  vpc_subnets = {
    public = { type = "public", newbits = 8, netnum_base = 0 }
    app    = { type = "private", newbits = 4, netnum_base = 1 }
  }

  vpc = {
    cidr              = var.vpc_cidr
    azs               = var.azs
    subnets           = local.vpc_subnets
    nat_mode          = var.nat_mode
    gateway_endpoints = toset(["s3"])
  }
}

module "vpc" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/vpc/aws"
  version = "~> 0.2.1"

  name              = local.name_prefix
  cidr              = local.vpc.cidr
  azs               = local.vpc.azs
  subnets           = local.vpc.subnets
  nat_mode          = local.vpc.nat_mode
  gateway_endpoints = local.vpc.gateway_endpoints
}
