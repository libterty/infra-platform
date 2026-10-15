locals {
  # Single decision points, published for the downstream stacks to follow.
  alb_https = jsonencode({ enabled = var.alb_ingress.https })
  db_proxy  = jsonencode({ enabled = var.data_stores["db"].proxy })
  data_access = jsonencode({
    for d in keys(var.data_stores) : d => sort([for s, cfg in var.services : s if contains(cfg.data_access, d)])
  })
  # Kept apart from data_access: iam-app checks that list against the services, and Runtime names would break that check.
  agent_data_access = jsonencode({
    for d in keys(var.data_stores) : d => sort([for r, cfg in var.agent_runtimes : r if contains(cfg.data_access, d)])
    if length([for r, cfg in var.agent_runtimes : r if contains(cfg.data_access, d)]) > 0
  })

  published_strings = merge(
    {
      vpc_id    = local.vpc_id
      vpc_cidr  = local.vpc_cidr
      sg_alb_id = module.sg.security_group_ids["alb"]
      nat       = jsonencode(local.nat)
      # SSM rejects an empty list, so this is JSON in a String; it is "[]" when no endpoint is created. application checks it when tracing runs without a NAT.
      interface_endpoints = jsonencode(sort(tolist(local.interface_endpoints.services)))
      alb_https           = local.alb_https
      db_proxy            = local.db_proxy
      data_access         = local.data_access
      agent_data_access   = local.agent_data_access
    },
    { for s, k in local.service_key : "sg_${k}_id" => module.sg.security_group_ids[k] },
    { for r, k in local.agent_key : "sg_${k}_id" => module.sg.security_group_ids[k] },
    { for d in keys(var.data_stores) : "sg_${d}_id" => module.sg.security_group_ids[d] },
    { for d in keys(var.data_stores) : "sg_${d}_proxy_id" => module.sg.security_group_ids["${d}_proxy"] },
    length(var.interface_endpoints.services) > 0 ? { sg_vpce_id = module.vpce.security_group_id } : {},
  )

  published_lists = merge(
    { azs = local.azs },
    { for t, ids in local.subnet_ids : "subnet_ids_${t}" => ids },
    { for t, cidrs in local.subnet_cidrs : "subnet_cidrs_${t}" => cidrs },
  )
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "network"
  strings    = local.published_strings
  lists      = local.published_lists
}
