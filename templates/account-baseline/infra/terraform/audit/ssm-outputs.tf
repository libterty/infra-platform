locals {
  published_strings = {
    trail_arn            = module.trail.arn
    config_recorder_name = module.config_recorder.recorder_name
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "audit"
  strings    = local.published_strings
}
