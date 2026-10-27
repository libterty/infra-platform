# SSM refuses an empty value and a missing key breaks readers, so no endpoint publishes {"enabled":false}.
locals {
  published_strings = {
    endpoint = !local.enabled ? jsonencode({ enabled = false }) : jsonencode({
      enabled = true
      name    = module.endpoint[0].endpoint_name
      arn     = module.endpoint[0].endpoint_arn
    })
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "inference"
  strings    = local.published_strings
}
