locals {
  repositories = {
    for s in var.services : s => {
      name            = "${local.name_prefix}-${s}"
      kms_key_arn     = module.in.strings["kms_key_arn"]
      lifecycle_rules = var.lifecycle_rules
    }
  }
}

module "ecr" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/ecr-repository/aws"
  version  = "~> 0.1.0"
  for_each = local.repositories

  name            = each.value.name
  kms_key_arn     = each.value.kms_key_arn
  lifecycle_rules = each.value.lifecycle_rules
}

locals {
  mirror_repositories = {
    for m in var.mirrored_images : m => {
      name            = "${local.name_prefix}-mirror-${m}"
      kms_key_arn     = module.in.strings["kms_key_arn"]
      lifecycle_rules = var.lifecycle_rules
    }
  }
}

module "ecr_mirror" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/ecr-repository/aws"
  version  = "~> 0.1.0"
  for_each = local.mirror_repositories

  name            = each.value.name
  kms_key_arn     = each.value.kms_key_arn
  lifecycle_rules = each.value.lifecycle_rules
}

locals {
  agent_repositories = {
    for r in var.agent_runtimes : r => {
      name            = "${local.name_prefix}-agent-${r}"
      kms_key_arn     = module.in.strings["kms_key_arn"]
      lifecycle_rules = var.lifecycle_rules
    }
  }
}

module "ecr_agent" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/ecr-repository/aws"
  version  = "~> 0.1.0"
  for_each = local.agent_repositories

  name            = each.value.name
  kms_key_arn     = each.value.kms_key_arn
  lifecycle_rules = each.value.lifecycle_rules
}
