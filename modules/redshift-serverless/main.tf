locals {
  # require_ssl is fixed; user activity logging is only a parameter when its log type is exported.
  config_parameters = merge(
    var.config_parameters,
    { require_ssl = "true" },
    contains(var.log_exports, "useractivitylog") ? { enable_user_activity_logging = "true" } : {},
  )
}

# The namespace has no final snapshot attribute: destroying it deletes the data.
resource "aws_redshiftserverless_namespace" "this" {
  namespace_name = var.name
  db_name        = var.db_name
  admin_username = var.admin_username

  # The password is never an input: Redshift generates it and keeps it in Secrets Manager under our key.
  manage_admin_password            = true
  admin_password_secret_kms_key_id = var.kms_key_arn

  # Encryption is not optional: the key is a required input.
  kms_key_id = var.kms_key_arn

  iam_roles            = var.iam_role_arns
  default_iam_role_arn = var.default_iam_role_arn

  # Audit logs go to CloudWatch Logs (/aws/redshift/serverless/<namespace>/<type>), not S3.
  log_exports = var.log_exports

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name = var.name

  base_capacity = var.base_capacity
  max_capacity  = var.max_capacity

  subnet_ids           = var.subnet_ids
  security_group_ids   = var.security_group_ids
  enhanced_vpc_routing = var.enhanced_vpc_routing
  publicly_accessible  = false

  dynamic "config_parameter" {
    for_each = local.config_parameters

    content {
      parameter_key   = config_parameter.key
      parameter_value = config_parameter.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_redshiftserverless_usage_limit" "this" {
  count = var.usage_limit_rpu_hours == null ? 0 : 1

  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "serverless-compute"
  amount        = var.usage_limit_rpu_hours
  period        = "monthly"
  breach_action = "deactivate"
}
