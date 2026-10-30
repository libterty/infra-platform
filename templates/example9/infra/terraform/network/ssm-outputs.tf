locals {
  published_strings = {
    vpc_id   = module.vpc.vpc_id
    vpc_cidr = module.vpc.vpc_cidr
  }

  published_lists = {
    app_subnet_ids = module.vpc.subnet_ids["app"]
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "network"
  strings    = local.published_strings
  lists      = local.published_lists
}
