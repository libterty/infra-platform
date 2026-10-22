locals {
  # Slots are counted in units of each tier's own subnet size. With a /16 and up to three AZs the ranges are:
  # public and db /24 at the low end, app /19 at 10.x.64.0-159.255, agent /19 at 10.x.160.0-255.255.
  vpc_subnets = {
    public = { type = "public", newbits = 8, netnum_base = 0 }
    app    = { type = "private", newbits = 3, netnum_base = 2 }
    agent  = { type = "private", newbits = 3, netnum_base = 5 }
    db     = { type = "isolated", newbits = 8, netnum_base = 10 }
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
  version = "~> 0.1.0"

  name              = local.name_prefix
  cidr              = local.vpc.cidr
  azs               = local.vpc.azs
  subnets           = local.vpc.subnets
  nat_mode          = local.vpc.nat_mode
  gateway_endpoints = local.vpc.gateway_endpoints
}
