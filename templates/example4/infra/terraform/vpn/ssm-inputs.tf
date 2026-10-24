locals {
  ssm_input_strings = {
    kms_key_arn      = "foundation/kms_key_arn"
    vpc_id           = "network/vpc_id"
    vpc_cidr         = "network/vpc_cidr"
    sg_client_vpn_id = "network/sg_client_vpn_id"
  }
  ssm_input_lists = {
    subnet_ids_data         = "network/subnet_ids_data"
    subnet_cidrs_data       = "network/subnet_cidrs_data"
    route_table_ids_private = "network/route_table_ids_private"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
