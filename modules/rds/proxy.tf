resource "aws_cloudwatch_log_group" "proxy" {
  count = var.proxy != null ? 1 : 0

  name              = "/aws/rds/proxy/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "/aws/rds/proxy/${var.name}" })
}

resource "aws_db_proxy" "this" {
  count = var.proxy != null ? 1 : 0

  name                   = var.name
  engine_family          = "POSTGRESQL"
  role_arn               = var.proxy.role_arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.proxy.security_group_ids
  require_tls            = var.proxy.require_tls
  idle_client_timeout    = var.proxy.idle_client_timeout
  debug_logging          = var.proxy.debug_logging

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = local.master_secret_arn
  }

  tags = merge(var.tags, { Name = var.name })

  depends_on = [aws_cloudwatch_log_group.proxy]
}

resource "aws_db_proxy_default_target_group" "this" {
  count = var.proxy != null ? 1 : 0

  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent      = var.proxy.max_connections_percent
    max_idle_connections_percent = var.proxy.max_idle_connections_percent
  }
}

resource "aws_db_proxy_target" "this" {
  count = var.proxy != null ? 1 : 0

  db_proxy_name          = aws_db_proxy.this[0].name
  target_group_name      = aws_db_proxy_default_target_group.this[0].name
  db_instance_identifier = local.is_rds ? aws_db_instance.this[0].identifier : null
  db_cluster_identifier  = local.is_rds ? null : aws_rds_cluster.this[0].cluster_identifier

  # The writer must exist before the Proxy registers the cluster as a target.
  depends_on = [aws_rds_cluster_instance.this]
}

resource "aws_db_proxy_endpoint" "read_only" {
  count = var.proxy != null && local.has_reader ? 1 : 0

  db_proxy_name          = aws_db_proxy.this[0].name
  db_proxy_endpoint_name = "${var.name}-ro"
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.proxy.security_group_ids
  target_role            = "READ_ONLY"

  tags = merge(var.tags, { Name = "${var.name}-ro" })

  depends_on = [aws_db_proxy_target.this]
}
