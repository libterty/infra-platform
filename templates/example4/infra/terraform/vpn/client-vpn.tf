locals {
  # Clients may reach the data tier only: one authorization rule per data subnet CIDR (design section 4).
  client_vpn = var.client_vpn == null ? null : {
    name                   = "${local.name_prefix}-client-vpn"
    kms_key_arn            = module.in.strings["kms_key_arn"]
    server_certificate_arn = var.client_vpn.server_certificate_arn
    authentication         = var.client_vpn.authentication
    client_cidr_block      = var.client_vpn.client_cidr_block
    vpc_id                 = module.in.strings["vpc_id"]
    vpc_cidr_blocks        = [module.in.strings["vpc_cidr"]]
    subnet_ids             = slice(module.in.lists["subnet_ids_data"], 0, var.client_vpn.associated_subnet_count)
    security_group_ids     = [module.in.strings["sg_client_vpn_id"]]
    authorization_rules = [
      for c in module.in.lists["subnet_cidrs_data"] : { target_cidr = c, access_group_id = null, description = "data subnet" }
    ]
    session_timeout_hours = var.client_vpn.session_timeout_hours
    dns_servers           = var.client_vpn.dns_servers
    log_retention_days    = var.client_vpn.log_retention_days
  }
}

module "client_vpn" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/client-vpn/aws"
  version = "~> 0.1.0"
  count   = var.client_vpn == null ? 0 : 1

  name                   = local.client_vpn.name
  kms_key_arn            = local.client_vpn.kms_key_arn
  server_certificate_arn = local.client_vpn.server_certificate_arn
  authentication         = local.client_vpn.authentication
  client_cidr_block      = local.client_vpn.client_cidr_block
  vpc_id                 = local.client_vpn.vpc_id
  vpc_cidr_blocks        = local.client_vpn.vpc_cidr_blocks
  subnet_ids             = local.client_vpn.subnet_ids
  security_group_ids     = local.client_vpn.security_group_ids
  authorization_rules    = local.client_vpn.authorization_rules
  session_timeout_hours  = local.client_vpn.session_timeout_hours
  dns_servers            = local.client_vpn.dns_servers
  log_retention_days     = local.client_vpn.log_retention_days
}
