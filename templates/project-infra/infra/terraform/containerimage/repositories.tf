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
  source   = "../../../../../modules/ecr-repository"
  for_each = local.repositories

  name            = each.value.name
  kms_key_arn     = each.value.kms_key_arn
  lifecycle_rules = each.value.lifecycle_rules
}
