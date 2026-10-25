locals {
  published_strings = {
    vpc_id             = module.vpc.vpc_id
    vpc_cidr           = module.vpc.vpc_cidr
    sg_opensearch_id   = module.sg.security_group_ids["opensearch"]
    sg_firehose_id     = module.sg.security_group_ids["firehose"]
    sg_sagemaker_id    = module.sg.security_group_ids["sagemaker"]
    sg_client_vpn_id   = module.sg.security_group_ids["client_vpn"]
    sg_search_admin_id = module.sg.security_group_ids["search_admin"]
  }

  published_lists = {
    azs               = module.vpc.azs
    subnet_ids_app    = module.vpc.subnet_ids["app"]
    subnet_ids_data   = module.vpc.subnet_ids["data"]
    subnet_cidrs_data = module.vpc.subnet_cidrs["data"]
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
