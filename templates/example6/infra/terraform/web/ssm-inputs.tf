locals {
  ssm_input_strings = {
    zone_id             = "dns/zone_id"
    zone_name           = "dns/zone_name"
    web_certificate_arn = "certificate/web_certificate_arn"
    api_endpoint        = "api/api_endpoint"
  }
  ssm_input_lists = {}
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}
