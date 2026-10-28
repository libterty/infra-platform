locals {
  published_strings = {
    zone_id   = module.zone.zone_id
    zone_name = module.zone.name
  }

  published_lists = {
    name_servers = module.zone.name_servers
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "dns"
  strings    = local.published_strings
  lists      = local.published_lists
}
