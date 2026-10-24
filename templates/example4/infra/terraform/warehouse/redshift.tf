locals {
  kms_key_arn     = module.in.strings["kms_key_arn"]
  subnet_ids_data = module.in.lists["subnet_ids_data"]
  iam_role_arn    = module.in.strings["role_redshift_arn"]
  sg_redshift_id  = module.in.strings["sg_redshift_id"]
}

# Exactly one of the two modules is created. The guard is in depends_on so it sits in the same plan as the database.
module "serverless" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/redshift-serverless/aws"
  version = "~> 0.1.0"
  count   = var.warehouse_mode == "serverless" ? 1 : 0

  name                  = "${local.name_prefix}-warehouse"
  db_name               = var.serverless.db_name
  kms_key_arn           = local.kms_key_arn
  iam_role_arns         = [local.iam_role_arn]
  default_iam_role_arn  = local.iam_role_arn
  base_capacity         = var.serverless.base_capacity
  max_capacity          = var.serverless.max_capacity
  usage_limit_rpu_hours = var.serverless.usage_limit_rpu_hours
  subnet_ids            = local.subnet_ids_data
  enhanced_vpc_routing  = var.serverless.enhanced_vpc_routing
  security_group_ids    = [local.sg_redshift_id]

  depends_on = [terraform_data.warehouse_mode_guard]
}

module "provisioned" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/redshift-cluster/aws"
  version = "~> 0.1.0"
  count   = var.warehouse_mode == "provisioned" ? 1 : 0

  name                              = "${local.name_prefix}-warehouse"
  database_name                     = var.provisioned.database_name
  node_type                         = var.provisioned.node_type
  number_of_nodes                   = var.provisioned.number_of_nodes
  kms_key_arn                       = local.kms_key_arn
  iam_role_arns                     = [local.iam_role_arn]
  default_iam_role_arn              = local.iam_role_arn
  subnet_ids                        = local.subnet_ids_data
  security_group_ids                = [local.sg_redshift_id]
  automated_snapshot_retention_days = var.provisioned.automated_snapshot_retention_days
  skip_final_snapshot               = var.provisioned.skip_final_snapshot
  multi_az                          = var.provisioned.multi_az
  enhanced_vpc_routing              = var.provisioned.enhanced_vpc_routing

  depends_on = [terraform_data.warehouse_mode_guard]
}

locals {
  # The two modules have different output types, so a conditional cannot merge them: collapse the one-element lists.
  warehouse = one(concat(
    [for m in module.serverless : {
      mode             = "serverless"
      host             = m.endpoint_address
      port             = m.port
      database         = m.database_name
      admin_secret_arn = m.admin_secret_arn
    }],
    [for m in module.provisioned : {
      mode             = "provisioned"
      host             = m.endpoint_address
      port             = m.port
      database         = m.database_name
      admin_secret_arn = m.admin_secret_arn
    }],
  ))
}
