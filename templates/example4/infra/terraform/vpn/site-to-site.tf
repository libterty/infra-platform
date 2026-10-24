locals {
  # A new virtual private gateway on the network VPC (design D9); the pre-shared key stays in Secrets Manager.
  site_to_site = var.site_to_site == null ? null : {
    name                      = "${local.name_prefix}-site-to-site"
    kms_key_arn               = module.in.strings["kms_key_arn"]
    vpc_id                    = module.in.strings["vpc_id"]
    vpn_gateway               = var.site_to_site.amazon_side_asn == null ? {} : { amazon_side_asn = var.site_to_site.amazon_side_asn }
    customer_gateway          = var.site_to_site.customer_gateway
    routing                   = var.site_to_site.routing
    propagate_route_table_ids = module.in.lists["route_table_ids_private"]
    log_retention_days        = var.site_to_site.log_retention_days
  }
}

module "site_to_site" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/vpn-site-to-site/aws"
  version = "~> 0.1.0"
  count   = var.site_to_site == null ? 0 : 1

  name                      = local.site_to_site.name
  kms_key_arn               = local.site_to_site.kms_key_arn
  vpc_id                    = local.site_to_site.vpc_id
  vpn_gateway               = local.site_to_site.vpn_gateway
  customer_gateway          = local.site_to_site.customer_gateway
  routing                   = local.site_to_site.routing
  propagate_route_table_ids = local.site_to_site.propagate_route_table_ids
  log_retention_days        = local.site_to_site.log_retention_days
}
