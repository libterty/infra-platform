locals {
  interface_endpoints = {
    services      = var.bedrock_endpoints_enabled ? toset(["bedrock", "bedrock-agentcore", "bedrock-runtime"]) : toset([])
    allowed_cidrs = [var.vpc_cidr]
    subnet_ids    = module.vpc.subnet_ids["app"]
  }
}

module "vpce" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/vpc-interface-endpoints/aws"
  version = "~> 0.1.0"

  name          = local.name_prefix
  vpc_id        = module.vpc.vpc_id
  allowed_cidrs = local.interface_endpoints.allowed_cidrs
  subnet_ids    = local.interface_endpoints.subnet_ids
  services      = local.interface_endpoints.services
}
