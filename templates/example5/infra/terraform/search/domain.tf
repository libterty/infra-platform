locals {
  domain = {
    name                    = "${local.name_prefix}-search"
    engine_version          = var.engine_version
    hot                     = var.hot
    dedicated_master        = var.dedicated_master
    warm                    = var.warm
    cold_storage            = var.cold_storage
    availability_zone_count = var.availability_zone_count
    subnet_ids              = module.in.lists["subnet_ids_data"]
    security_group_ids      = [module.in.strings["sg_opensearch_id"]]
    kms_key_arn             = module.in.strings["kms_key_arn"]
    master_user_secret_arn  = module.in.strings["opensearch_master_secret_arn"]
    # Only the Firehose role signs requests (SigV4); people use basic auth, which this policy does not cover (v7 design section 4).
    access_principal_arns = [module.in.strings["role_firehose_arn"]]
    log_retention_days    = var.log_retention_days
  }
}

module "domain" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/opensearch-domain/aws"
  version = "~> 0.1.0"

  name                    = local.domain.name
  engine_version          = local.domain.engine_version
  hot                     = local.domain.hot
  dedicated_master        = local.domain.dedicated_master
  warm                    = local.domain.warm
  cold_storage            = local.domain.cold_storage
  availability_zone_count = local.domain.availability_zone_count
  subnet_ids              = local.domain.subnet_ids
  security_group_ids      = local.domain.security_group_ids
  kms_key_arn             = local.domain.kms_key_arn
  master_user_secret_arn  = local.domain.master_user_secret_arn
  access_principal_arns   = local.domain.access_principal_arns
  log_retention_days      = local.domain.log_retention_days
}
