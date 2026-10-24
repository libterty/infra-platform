locals {
  tables = {
    for k, t in var.tables : k => merge(t, { name = "${local.name_prefix}-${replace(k, "_", "-")}" })
  }
}

# On-demand billing (the module default), CMK encryption and deletion protection (default on).
module "table" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/dynamodb-table/aws"
  version  = "~> 0.1.0"
  for_each = local.tables

  name                        = each.value.name
  kms_key_arn                 = local.kms_key_arn
  hash_key                    = each.value.hash_key
  range_key                   = each.value.range_key
  attributes                  = each.value.attributes
  ttl_attribute               = each.value.ttl_attribute
  point_in_time_recovery_days = each.value.point_in_time_recovery_days
}
