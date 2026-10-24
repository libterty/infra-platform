data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# The master user comes from a secret the caller owns: the module has no password variable.
# This read and the domain attribute below are the two copies of the password in state (README, Notes).
data "aws_secretsmanager_secret_version" "master" {
  secret_id = var.master_user_secret_arn
}

locals {
  # try() keeps a malformed secret from failing here; the precondition on the domain reports it.
  master = try(jsondecode(data.aws_secretsmanager_secret_version.master.secret_string), {})

  # Built from names, not from resource attributes, so the policies below are known at plan time.
  domain_arn = "arn:${data.aws_partition.current.partition}:es:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:domain/${var.name}"
  log_group_names = {
    for t in var.log_types : t => "/aws/OpenSearchService/domains/${var.name}/${lower(replace(t, "_", "-"))}"
  }
  log_group_arn_prefix = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group"

  access_policies = length(var.access_principal_arns) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.access_principal_arns }
      Action    = "es:ESHttp*"
      Resource  = "${local.domain_arn}/*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_group_names

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = each.value })
}

# OpenSearch checks it can write to the log group when the domain is created or updated, so the policy comes first.
# One account-level policy per domain (documented form). CloudWatch Logs allows 10 resource policies per Region.
resource "aws_cloudwatch_log_resource_policy" "this" {
  policy_name = "OpenSearchService-${var.name}-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OpenSearchLogPublishing"
      Effect    = "Allow"
      Principal = { Service = "es.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = [for name in values(local.log_group_names) : "${local.log_group_arn_prefix}:${name}:*"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = local.domain_arn }
      }
    }]
  })
}

resource "aws_opensearch_domain" "this" {
  domain_name     = var.name
  engine_version  = var.engine_version
  access_policies = local.access_policies

  cluster_config {
    instance_type  = var.hot.instance_type
    instance_count = var.hot.instance_count

    dedicated_master_enabled = var.dedicated_master != null
    dedicated_master_type    = try(var.dedicated_master.instance_type, null)
    dedicated_master_count   = try(var.dedicated_master.count, null)

    warm_enabled = var.warm != null
    warm_type    = try(var.warm.instance_type, null)
    warm_count   = try(var.warm.count, null)

    cold_storage_options {
      enabled = var.cold_storage
    }

    zone_awareness_enabled        = true
    multi_az_with_standby_enabled = var.multi_az_with_standby

    zone_awareness_config {
      availability_zone_count = var.availability_zone_count
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.hot.ebs.volume_type
    volume_size = var.hot.ebs.volume_size
    iops        = var.hot.ebs.iops
    throughput  = var.hot.ebs.throughput
  }

  # Fixed security settings: not inputs, so no caller can turn them off.
  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    anonymous_auth_enabled         = false

    master_user_options {
      master_user_name     = local.master.username
      master_user_password = local.master.password
    }
  }

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  dynamic "log_publishing_options" {
    for_each = aws_cloudwatch_log_group.this

    content {
      log_type                 = log_publishing_options.key
      cloudwatch_log_group_arn = log_publishing_options.value.arn
      enabled                  = true
    }
  }

  auto_tune_options {
    desired_state       = var.auto_tune ? "ENABLED" : "DISABLED"
    use_off_peak_window = var.auto_tune
  }

  dynamic "off_peak_window_options" {
    for_each = var.off_peak_window_start == null ? [] : [var.off_peak_window_start]

    content {
      enabled = true

      off_peak_window {
        window_start_time {
          hours   = off_peak_window_options.value
          minutes = 0
        }
      }
    }
  }

  dynamic "snapshot_options" {
    for_each = var.automated_snapshot_start_hour == null ? [] : [var.automated_snapshot_start_hour]

    content {
      automated_snapshot_start_hour = snapshot_options.value
    }
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition = (
        can(tostring(local.master.username)) &&
        can(tostring(local.master.password)) &&
        length(try(local.master.username, "")) > 0 &&
        length(try(local.master.password, "")) >= 8 &&
        length(try(local.master.password, "")) <= 128
      )
      error_message = "the master secret must be JSON with a non-empty \"username\" and a \"password\" of 8-128 characters."
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.this]
}
