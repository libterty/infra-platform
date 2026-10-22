locals {
  published_strings = {
    vpc_id         = module.vpc.vpc_id
    vpc_cidr       = module.vpc.vpc_cidr
    alb_sg_id      = module.sg.security_group_ids["alb"]
    app_sg_id      = module.sg.security_group_ids["app"]
    agent_sg_id    = module.sg.security_group_ids["agent"]
    db_sg_id       = module.sg.security_group_ids["db"]
    db_proxy_sg_id = module.sg.security_group_ids["db_proxy"]
    cache_sg_id    = module.sg.security_group_ids["cache"]
    # The group exists even when bastion_enabled is false (it then has no rules), so downstream stacks can always read it.
    bastion_sg_id = module.sg.security_group_ids["bastion"]
    node_sg_id    = module.sg.security_group_ids["node"]
    eks_api_sg_id = module.sg.security_group_ids["eks_api"]
    # SSM rejects an empty map, so this is JSON in a String: peering name => connection ID, "{}" without a peering.
    peering_connections = jsonencode(var.peering == null ? {} : { peer = module.peering[0].peering_connection_id })
  }

  published_lists = {
    public_subnet_ids = module.vpc.subnet_ids["public"]
    app_subnet_ids    = module.vpc.subnet_ids["app"]
    agent_subnet_ids  = module.vpc.subnet_ids["agent"]
    db_subnet_ids     = module.vpc.subnet_ids["db"]
    # Control-plane ENIs and the interface endpoints sit in the app subnets; the system NetworkPolicies allow these.
    app_subnet_cidrs = module.vpc.subnet_cidrs["app"]
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "network"
  strings    = local.published_strings
  lists      = local.published_lists
}
