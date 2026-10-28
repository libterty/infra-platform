# Single-table design with generic PK and SK string keys; the application decides what goes into them. Add global
# secondary indexes here when access patterns need them: the iam stack already allows the table's indexes.
locals {
  table = {
    name                        = "${local.name_prefix}-app"
    kms_key_arn                 = module.in.strings["kms_key_arn"]
    hash_key                    = "PK"
    range_key                   = "SK"
    attributes                  = { PK = "S", SK = "S" }
    billing_mode                = "PAY_PER_REQUEST"
    point_in_time_recovery_days = var.point_in_time_recovery_days
    deletion_protection         = var.deletion_protection
  }
}

module "table" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/dynamodb-table/aws"
  version = "~> 0.1.0"

  name                        = local.table.name
  kms_key_arn                 = local.table.kms_key_arn
  hash_key                    = local.table.hash_key
  range_key                   = local.table.range_key
  attributes                  = local.table.attributes
  billing_mode                = local.table.billing_mode
  point_in_time_recovery_days = local.table.point_in_time_recovery_days
  deletion_protection         = local.table.deletion_protection
}
