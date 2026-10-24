locals {
  to_opensearch = var.opensearch != null
  direct_put    = var.source_stream_arn == null
  log_group     = "/aws/kinesisfirehose/${var.name}"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.log_group })
}

resource "aws_cloudwatch_log_stream" "destination" {
  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.this.name
}

# Only the OpenSearch destination has a separate S3 backup path.
resource "aws_cloudwatch_log_stream" "backup" {
  count = local.to_opensearch ? 1 : 0

  name           = "BackupDelivery"
  log_group_name = aws_cloudwatch_log_group.this.name
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = var.name
  destination = local.to_opensearch ? "opensearch" : "extended_s3"

  dynamic "kinesis_source_configuration" {
    for_each = local.direct_put ? [] : [var.source_stream_arn]

    content {
      kinesis_stream_arn = kinesis_source_configuration.value
      role_arn           = var.role_arn
    }
  }

  # SSE is only available for Direct PUT; a Kinesis source is encrypted on the source stream.
  dynamic "server_side_encryption" {
    for_each = local.direct_put ? [var.kms_key_arn] : []

    content {
      enabled  = true
      key_type = "CUSTOMER_MANAGED_CMK"
      key_arn  = server_side_encryption.value
    }
  }

  dynamic "extended_s3_configuration" {
    for_each = local.to_opensearch ? [] : [var.s3]

    content {
      role_arn            = var.role_arn
      bucket_arn          = extended_s3_configuration.value.bucket_arn
      prefix              = extended_s3_configuration.value.prefix
      error_output_prefix = extended_s3_configuration.value.error_output_prefix
      buffering_size      = extended_s3_configuration.value.buffering_size
      buffering_interval  = extended_s3_configuration.value.buffering_interval
      compression_format  = extended_s3_configuration.value.compression
      kms_key_arn         = var.kms_key_arn

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.this.name
        log_stream_name = aws_cloudwatch_log_stream.destination.name
      }
    }
  }

  dynamic "opensearch_configuration" {
    for_each = local.to_opensearch ? [var.opensearch] : []

    content {
      role_arn              = var.role_arn
      domain_arn            = opensearch_configuration.value.domain_arn
      index_name            = opensearch_configuration.value.index_name
      index_rotation_period = opensearch_configuration.value.index_rotation_period
      retry_duration        = opensearch_configuration.value.retry_seconds
      s3_backup_mode        = "FailedDocumentsOnly"

      vpc_config {
        role_arn           = var.role_arn
        subnet_ids         = opensearch_configuration.value.subnet_ids
        security_group_ids = opensearch_configuration.value.security_group_ids
      }

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.this.name
        log_stream_name = aws_cloudwatch_log_stream.destination.name
      }

      s3_configuration {
        role_arn            = var.role_arn
        bucket_arn          = var.s3.bucket_arn
        prefix              = var.s3.prefix
        error_output_prefix = var.s3.error_output_prefix
        buffering_size      = var.s3.buffering_size
        buffering_interval  = var.s3.buffering_interval
        compression_format  = var.s3.compression
        kms_key_arn         = var.kms_key_arn

        cloudwatch_logging_options {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.this.name
          log_stream_name = aws_cloudwatch_log_stream.backup[0].name
        }
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
