locals {
  # SG keys are snake_case: service order-api has the key order_api.
  service_key = { for s in keys(var.services) : s => replace(s, "-", "_") }
  # Runtime order-bot has the key agent_order_bot.
  agent_key = { for r in keys(var.agent_runtimes) : r => "agent_${replace(r, "-", "_")}" }

  security_groups = merge(
    { alb = { name = "${local.name_prefix}-alb", description = "ALB" } },
    { for s, k in local.service_key : k => { name = "${local.name_prefix}-${s}", description = "${s} service" } },
    { for r, k in local.agent_key : k => { name = "${local.name_prefix}-agent-${r}", description = "${r} AgentCore Runtime" } },
    { for d in keys(var.data_stores) : d => { name = "${local.name_prefix}-${d}", description = "${d} data store" } },
    # The Proxy security group is always created (no cost); it has no rules unless the data store uses a Proxy.
    { for d in keys(var.data_stores) : "${d}_proxy" => { name = "${local.name_prefix}-${d}-proxy", description = "${d} RDS Proxy" } },
  )

  alb_ports = var.alb_ingress.https ? [443, 80] : [80]
  alb_sources = merge(
    { for c in var.alb_ingress.cidrs : "cidr_${replace(replace(c, ".", "_"), "/", "_")}" => { cidr_ipv4 = c, prefix_list_id = null } },
    { for p in var.alb_ingress.prefix_list_ids : "pl_${replace(p, "-", "_")}" => { cidr_ipv4 = null, prefix_list_id = p } },
  )

  alb_ingress_rules = {
    for pair in setproduct(local.alb_ports, keys(local.alb_sources)) : "alb_in_${pair[0]}_${pair[1]}" => {
      security_group = "alb"
      type           = "ingress"
      description    = pair[0] == 443 ? "clients" : (var.alb_ingress.https ? "redirect to https" : "clients")
      from_port      = pair[0]
      peer_group     = null
      cidr_ipv4      = local.alb_sources[pair[1]].cidr_ipv4
      prefix_list_id = local.alb_sources[pair[1]].prefix_list_id
      allow_internet = local.alb_sources[pair[1]].cidr_ipv4 == "0.0.0.0/0"
    }
  }

  # One entry per allowed connection: from -> to on port. Security groups are stateful but Terraform removes the
  # default allow-all egress, so each connection needs an egress rule on the source and an ingress rule on the target.
  connections = concat(
    [for s, k in local.service_key : { from = "alb", to = k, port = var.services[s].port } if var.services[s].from_alb],
    flatten([for s, k in local.service_key : [for c in distinct(var.services[s].callers) : { from = local.service_key[c], to = k, port = var.services[s].port }]]),
    flatten([for s, k in local.service_key : [
      for d in distinct(var.services[s].data_access) : { from = k, to = var.data_stores[d].proxy ? "${d}_proxy" : d, port = var.data_stores[d].port }
    ]]),
    [for d, cfg in var.data_stores : { from = "${d}_proxy", to = d, port = cfg.port } if cfg.proxy],
    # Runtimes have no ingress: they are called through the AgentCore API, not through the security group.
    flatten([for r, k in local.agent_key : [
      for d in distinct(var.agent_runtimes[r].data_access) : { from = k, to = var.data_stores[d].proxy ? "${d}_proxy" : d, port = var.data_stores[d].port }
    ]]),
  )

  connection_rules = merge(
    {
      for c in local.connections : "${c.from}_out_${c.to}" => {
        security_group = c.from
        type           = "egress"
        description    = "to ${c.to}"
        from_port      = c.port
        peer_group     = c.to
        cidr_ipv4      = null
        prefix_list_id = null
        allow_internet = false
      }
    },
    {
      for c in local.connections : "${c.to}_in_${c.from}" => {
        security_group = c.to
        type           = "ingress"
        description    = "from ${c.from}"
        from_port      = c.port
        peer_group     = c.from
        cidr_ipv4      = null
        prefix_list_id = null
        allow_internet = false
      }
    },
  )

  # Services reach AWS APIs through a NAT or a VPC endpoint, never anything else on the internet.
  service_egress_rules = {
    for s, k in local.service_key : "${k}_out_https" => {
      security_group = k
      type           = "egress"
      description    = "AWS APIs"
      from_port      = 443
      peer_group     = null
      cidr_ipv4      = "0.0.0.0/0"
      prefix_list_id = null
      allow_internet = false
    }
  }

  # Without a NAT, 443 can only reach the interface endpoints in the VPC, so the rule says so. Mode none exists only
  # for a VPC this stack creates, which has a single CIDR. Mode A reports external and keeps 0.0.0.0/0.
  agent_egress_rules = {
    for r, k in local.agent_key : "${k}_out_https" => {
      security_group = k
      type           = "egress"
      description    = local.nat.mode == "none" ? "VPC interface endpoints" : "AWS APIs"
      from_port      = 443
      peer_group     = null
      cidr_ipv4      = local.nat.mode == "none" ? local.vpc_cidr : "0.0.0.0/0"
      prefix_list_id = null
      allow_internet = false
    }
  }

  sg_rules = merge(local.alb_ingress_rules, local.connection_rules, local.service_egress_rules, local.agent_egress_rules)
}

module "sg" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/security-group/aws"
  version = "~> 0.1.0"

  vpc_id          = local.vpc_id
  security_groups = local.security_groups
  rules           = local.sg_rules
}
