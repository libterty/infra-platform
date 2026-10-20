locals {
  db = {
    name               = "${local.name_prefix}-db"
    deployment         = "aurora"
    engine_version     = var.engine_version
    database_name      = var.db_name
    aurora             = { instance_class = var.db_instance_class, reader_count = var.db_reader_count }
    subnet_ids         = module.in.lists["db_subnet_ids"]
    security_group_ids = [module.in.strings["db_sg_id"]]
    # Parameters that differ from the module defaults. pg_cron has to be preloaded and told its database.
    cluster_parameters = {
      log_temp_files           = "0"
      shared_preload_libraries = "pg_stat_statements,pg_cron"
      "cron.database_name"     = var.db_name
    }
    # shared_preload_libraries is static too, but the module always treats it as static.
    static_parameter_names   = toset(["cron.database_name"])
    alarm_config             = { connections_threshold = var.connections_threshold }
    backup_retention_days    = var.backup_retention_days
    deletion_protection      = var.deletion_protection
    skip_final_snapshot      = var.skip_final_snapshot
    log_retention_days       = var.log_retention_days
    sns_topic_arns           = [module.in.strings["alarm_topic_arn"]]
    proxy_security_group_ids = [module.in.strings["db_proxy_sg_id"]]
  }
}

module "db" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/rds/aws"
  version = "~> 0.2.0"

  name               = local.db.name
  deployment         = local.db.deployment
  engine_version     = local.db.engine_version
  database_name      = local.db.database_name
  aurora             = local.db.aurora
  subnet_ids         = local.db.subnet_ids
  security_group_ids = local.db.security_group_ids

  cluster_parameters     = local.db.cluster_parameters
  static_parameter_names = local.db.static_parameter_names
  alarm_config           = local.db.alarm_config

  backup_retention_days = local.db.backup_retention_days
  deletion_protection   = local.db.deletion_protection
  skip_final_snapshot   = local.db.skip_final_snapshot
  log_retention_days    = local.db.log_retention_days
  sns_topic_arns        = local.db.sns_topic_arns

  monitoring = { role_arn = module.monitoring_role.arn }

  proxy = {
    security_group_ids = local.db.proxy_security_group_ids
    role_arn           = module.proxy_role.arn
  }
}
