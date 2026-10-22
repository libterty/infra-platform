locals {
  # The peer network is reached from the app and agent tiers only.
  peering_route_table_ids = concat(module.vpc.route_table_ids["app"], module.vpc.route_table_ids["agent"])
}

module "peering" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/vpc-peering/aws"
  version = "~> 0.1.0"

  count = var.peering == null ? 0 : 1

  name            = "${local.name_prefix}-peer"
  vpc_id          = module.vpc.vpc_id
  vpc_cidr        = var.vpc_cidr
  peer_vpc_id     = var.peering.peer_vpc_id
  peer_owner_id   = var.peering.peer_owner_id
  peer_region     = var.peering.peer_region
  route_table_ids = local.peering_route_table_ids
  peer_cidrs      = var.peering.peer_cidrs
}
