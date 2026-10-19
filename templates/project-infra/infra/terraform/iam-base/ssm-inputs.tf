locals {
  ssm_input_strings = {
    kms_key_arn    = "foundation/kms_key_arn"
    app_secret_arn = "foundation/app_secret_arn"
    # JSON array of mirror names; "[]" when containerimage has no mirror.
    mirrored_images = "containerimage/mirrored_images"
    # JSON array of Runtime names; "[]" when containerimage has no Runtime.
    agent_runtimes = "containerimage/agent_runtimes"
  }
  ssm_input_lists = {
    services = "containerimage/services"
  }
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

# The repository ARNs are keyed by the service and mirror lists, which are themselves read from SSM, so they need a second read.
locals {
  service_key         = { for s in module.in.lists["services"] : s => replace(s, "-", "_") }
  ssm_service_strings = { for s, k in local.service_key : "ecr_${k}_arn" => "containerimage/ecr_${k}_arn" }

  mirror_key         = { for m in jsondecode(module.in.strings["mirrored_images"]) : m => replace(m, "-", "_") }
  ssm_mirror_strings = { for m, k in local.mirror_key : "ecr_mirror_${k}_arn" => "containerimage/ecr_mirror_${k}_arn" }

  agent_key         = { for r in jsondecode(module.in.strings["agent_runtimes"]) : r => replace(r, "-", "_") }
  ssm_agent_strings = { for r, k in local.agent_key : "ecr_agent_${k}_arn" => "containerimage/ecr_agent_${k}_arn" }
}

module "in_services" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_service_strings
}

module "in_mirrors" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_mirror_strings
}

module "in_agents" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to app.terraform.io/<org>/ssm-read/aws

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_agent_strings
}
