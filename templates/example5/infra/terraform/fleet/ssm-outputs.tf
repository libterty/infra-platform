locals {
  published_strings = {
    thing_group_fleet_arn      = module.fleet.thing_group_arns["${local.name_prefix}-fleet"]
    thing_group_unverified_arn = module.fleet.thing_group_arns["${local.name_prefix}-unverified"]
    thing_group_core_arn       = module.fleet.thing_group_arns["${local.name_prefix}-core"]
    role_alias_arn             = module.fleet.role_alias_arn
    provisioning_template_name = module.fleet.provisioning_template_name
    ota_signing_profile_name   = module.ota_signing.profile_name
    ota_job_template_arn       = module.ota_job.arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "fleet"
  strings    = local.published_strings
}
