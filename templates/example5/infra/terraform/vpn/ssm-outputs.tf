# SSM refuses an empty value and a missing key breaks readers, so a VPN that is off publishes {"enabled":false}.
locals {
  published_strings = {
    client_vpn = var.client_vpn == null ? jsonencode({ enabled = false }) : jsonencode({
      enabled     = true
      endpoint_id = module.client_vpn[0].endpoint_id
      dns_name    = module.client_vpn[0].dns_name
    })
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "vpn"
  strings    = local.published_strings
}
