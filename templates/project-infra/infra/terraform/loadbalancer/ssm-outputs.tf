locals {
  published_strings = {
    alb_arn           = module.alb.alb_arn
    alb_arn_suffix    = module.alb.alb_arn_suffix
    alb_dns_name      = module.alb.alb_dns_name
    alb_zone_id       = module.alb.alb_zone_id
    listener_arn      = module.alb.listener_arn
    listener_protocol = module.alb.listener_protocol
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "loadbalancer"
  strings    = local.published_strings
}
