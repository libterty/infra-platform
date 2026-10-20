locals {
  is_rds        = var.deployment == "rds"
  is_serverless = var.deployment == "aurora_serverless"
  is_aurora     = !local.is_rds
  major         = split(".", var.engine_version)[0]
  port          = 5432

  reader_count = (
    var.deployment == "aurora" ? var.aurora.reader_count :
    var.deployment == "aurora_serverless" ? var.serverless.reader_count :
    0
  )
  has_reader = local.is_aurora && local.reader_count > 0

  instance_identifiers = (
    local.is_rds ? [var.name] :
    [for i in range(1 + local.reader_count) : i == 0 ? "${var.name}-writer" : "${var.name}-reader-${i}"]
  )
  instances = { for i, id in local.instance_identifiers : (i == 0 ? "writer" : "reader-${i}") => id }

  identifier_type = local.is_rds ? "instance" : "cluster"
  log_group_name  = "/aws/rds/${local.identifier_type}/${var.name}/postgresql"

  # Defaults first, so caller parameters of the same name win.
  default_parameters = {
    log_min_duration_statement = "500"
    log_lock_waits             = "1"
    "rds.force_ssl"            = "1"
    shared_preload_libraries   = "pg_stat_statements"
  }
  # shared_preload_libraries is the only static parameter the module sets itself; callers list any other static
  # parameter they pass, because RDS rejects "immediate" for a static parameter.
  static_parameters = setunion(["shared_preload_libraries"], var.static_parameter_names)

  parameters = merge(local.default_parameters, local.is_rds ? var.instance_parameters : var.cluster_parameters)

  monitoring_interval = var.monitoring == null ? 0 : var.monitoring.interval
  monitoring_role_arn = var.monitoring == null ? null : var.monitoring.role_arn

  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${random_id.final_snapshot.hex}"

  master_secret_arn = local.is_rds ? aws_db_instance.this[0].master_user_secret[0].secret_arn : aws_rds_cluster.this[0].master_user_secret[0].secret_arn
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = var.name })
}

# Suffix keeps the final snapshot name unique when the DB is destroyed and recreated.
resource "random_id" "final_snapshot" {
  byte_length = 4
}

# Created ahead of the DB so retention and KMS are ours, not RDS's defaults.
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}
