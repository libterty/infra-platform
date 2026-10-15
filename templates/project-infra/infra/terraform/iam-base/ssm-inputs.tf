locals {
  ssm_input_strings = {
    kms_key_arn    = "foundation/kms_key_arn"
    app_secret_arn = "foundation/app_secret_arn"
  }
  ssm_input_lists = {
    services = "containerimage/services"
  }
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

# The repository ARNs are keyed by the service list, which is itself read from SSM, so they need a second read.
locals {
  service_key         = { for s in module.in.lists["services"] : s => replace(s, "-", "_") }
  ssm_service_strings = { for s, k in local.service_key : "ecr_${k}_arn" => "containerimage/ecr_${k}_arn" }
}

module "in_services" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_service_strings
}
