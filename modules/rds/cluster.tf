# Aurora provisioned and Serverless v2 share these addresses; switching between them is an in-place change.

resource "aws_rds_cluster_parameter_group" "this" {
  count = local.is_aurora ? 1 : 0

  name   = var.name
  family = "aurora-postgresql${local.major}"

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

resource "aws_db_parameter_group" "aurora_instance" {
  count = local.is_aurora && length(var.instance_parameters) > 0 ? 1 : 0

  name   = "${var.name}-instance"
  family = "aurora-postgresql${local.major}"

  dynamic "parameter" {
    for_each = var.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = contains(local.static_parameters, parameter.key) ? "pending-reboot" : "immediate"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-instance" })
}

resource "aws_rds_cluster" "this" {
  count = local.is_aurora ? 1 : 0

  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version
  port               = local.port

  database_name                 = var.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.this.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[0].name
  vpc_security_group_ids          = var.security_group_ids

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverless] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(var.tags, { Name = var.name })

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

resource "aws_rds_cluster_instance" "this" {
  count = local.is_aurora ? 1 + local.reader_count : 0

  identifier         = local.instance_identifiers[count.index]
  cluster_identifier = aws_rds_cluster.this[0].id
  engine             = aws_rds_cluster.this[0].engine
  engine_version     = aws_rds_cluster.this[0].engine_version
  instance_class     = local.is_serverless ? "db.serverless" : var.aurora.instance_class
  promotion_tier     = count.index == 0 ? 0 : 1

  db_subnet_group_name    = aws_db_subnet_group.this.name
  db_parameter_group_name = one(aws_db_parameter_group.aurora_instance[*].name)
  publicly_accessible     = false

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_days
  performance_insights_kms_key_id       = var.kms_key_arn
  monitoring_interval                   = local.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn

  tags = merge(var.tags, { Name = local.instance_identifiers[count.index] })
}
