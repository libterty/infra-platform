locals {
  # The data platform has no NAT and no interface endpoint (design K12); the gateway endpoints reach S3 and DynamoDB.
  # Each tier reserves slots for 4 AZs, so adding AZs later leaves existing subnets in place.
  vpc = {
    cidr     = var.vpc_cidr
    azs      = var.azs
    nat_mode = "none"
    subnets = {
      app  = { type = "private", newbits = 4, netnum_base = 0 }
      data = { type = "isolated", newbits = 7, netnum_base = 40 }
    }
    gateway_endpoints = toset(["s3", "dynamodb"])
    flow_log          = var.flow_log ? { destination_arn = module.in.strings["flow_log_bucket_arn"] } : null
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
  flow_log          = local.vpc.flow_log
}
