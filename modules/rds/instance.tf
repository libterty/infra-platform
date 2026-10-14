resource "aws_db_parameter_group" "rds" {
  count = local.is_rds ? 1 : 0

  name   = var.name
  family = "postgres${local.major}"

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = contains(local.static_parameters, parameter.key) ? "pending-reboot" : "immediate"
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_db_instance" "this" {
  count = local.is_rds ? 1 : 0

  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.rds.instance_class
  port           = local.port

  allocated_storage     = var.rds.allocated_storage
  max_allocated_storage = var.rds.max_allocated_storage
  storage_type          = var.rds.storage_type
  multi_az              = var.rds.multi_az
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                       = var.database_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.rds[0].name
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  enabled_cloudwatch_logs_exports       = ["postgresql"]
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_days
  performance_insights_kms_key_id       = var.kms_key_arn
  monitoring_interval                   = local.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn

  tags = merge(var.tags, { Name = var.name })

  depends_on = [aws_cloudwatch_log_group.postgresql]
}
