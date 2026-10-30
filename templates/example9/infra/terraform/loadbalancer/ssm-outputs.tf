locals {
  # application attaches the api service to this listener and admits this group in the api security group.
  published_strings = {
    listener_arn      = module.alb.listener_arn
    security_group_id = module.sg.security_group_ids["alb"]
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "loadbalancer"
  strings    = local.published_strings
}
