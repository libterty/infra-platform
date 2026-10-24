locals {
  # require_ssl and user activity logging (needed for the useractivitylog export) are fixed.
  parameters = merge(
    var.parameters,
    {
      require_ssl                  = "true"
      enable_user_activity_logging = "true"
    },
  )

  port = 5439
}

resource "aws_redshift_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_redshift_parameter_group" "this" {
  name   = var.name
  family = "redshift-2.0"

  dynamic "parameter" {
    for_each = local.parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_redshift_cluster" "this" {
  cluster_identifier = var.name
  database_name      = var.database_name
  node_type          = var.node_type
  cluster_type       = var.number_of_nodes == 1 ? "single-node" : "multi-node"
  number_of_nodes    = var.number_of_nodes
  multi_az           = var.multi_az
  port               = local.port

  # The password is never an input: Redshift generates it and keeps it in Secrets Manager under our key.
  master_username                   = var.master_username
  manage_master_password            = true
  master_password_secret_kms_key_id = var.kms_key_arn

  # Encryption is not optional: the key is a required input.
  encrypted  = true
  kms_key_id = var.kms_key_arn

  cluster_subnet_group_name    = aws_redshift_subnet_group.this.name
  cluster_parameter_group_name = aws_redshift_parameter_group.this.name
  vpc_security_group_ids       = var.security_group_ids
  enhanced_vpc_routing         = var.enhanced_vpc_routing
  publicly_accessible          = false

  iam_roles            = var.iam_role_arns
  default_iam_role_arn = var.default_iam_role_arn

  automated_snapshot_retention_period = var.automated_snapshot_retention_days
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${var.name}-final"

  tags = merge(var.tags, { Name = var.name })
}

# Audit logs go to CloudWatch Logs (/aws/redshift/cluster/<name>/<type>), not S3, so no bucket policy is needed.
resource "aws_redshift_logging" "this" {
  cluster_identifier   = aws_redshift_cluster.this.cluster_identifier
  log_destination_type = "cloudwatch"
  log_exports          = ["connectionlog", "userlog", "useractivitylog"]
}
