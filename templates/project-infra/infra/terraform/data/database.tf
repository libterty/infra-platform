locals {
  # Whether a Proxy exists is decided by the network stack (the security group rules live there); follow it.
  proxy_enabled = jsondecode(module.in.strings["db_proxy"]).enabled

  db_wiring = {
    subnet_ids                     = module.in.lists["subnet_ids_data"]
    security_group_ids             = [module.in.strings["sg_db_id"]]
    kms_key_arn                    = module.in.strings["kms_key_arn"]
    master_user_secret_kms_key_arn = module.in.strings["kms_key_arn"]
    monitoring                     = { role_arn = module.in.strings["role_rds_monitoring_arn"] }
    sns_topic_arns                 = [module.in.strings["alarm_topic_arn"]]
    proxy = local.proxy_enabled ? {
      security_group_ids = [module.in.strings["sg_db_proxy_id"]]
      role_arn           = module.in.strings["role_rds_proxy_arn"]
    } : null
  }
}

module "db" {
  source = "../../../../../modules/rds"
  count  = var.db == null ? 0 : 1

  name           = "${local.name_prefix}-db"
  deployment     = var.db.deployment
  engine_version = var.db.engine_version
  database_name  = var.db.database_name
  rds            = var.db.rds
  aurora         = var.db.aurora
  serverless     = var.db.serverless

  backup_retention_days = coalesce(var.db.backup_retention_days, 7)
  deletion_protection   = coalesce(var.db.deletion_protection, true)
  skip_final_snapshot   = coalesce(var.db.skip_final_snapshot, false)
  alarm_config          = var.db.alarm_config

  subnet_ids                     = local.db_wiring.subnet_ids
  security_group_ids             = local.db_wiring.security_group_ids
  kms_key_arn                    = local.db_wiring.kms_key_arn
  master_user_secret_kms_key_arn = local.db_wiring.master_user_secret_kms_key_arn
  monitoring                     = local.db_wiring.monitoring
  sns_topic_arns                 = local.db_wiring.sns_topic_arns
  proxy                          = local.db_wiring.proxy
}
