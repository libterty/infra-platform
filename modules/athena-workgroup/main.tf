resource "aws_athena_workgroup" "this" {
  name          = var.name
  force_destroy = var.force_destroy

  configuration {
    # Fixed on purpose: with enforcement on, clients cannot move the result location or weaken its encryption,
    # and AWS then ignores enable_minimum_encryption_configuration, so that flag is left unset.
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query

    engine_version {
      selected_engine_version = var.engine_version
    }

    result_configuration {
      output_location = "s3://${var.results_bucket_name}/${var.results_prefix}"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_athena_named_query" "this" {
  for_each = var.named_queries

  name        = each.key
  workgroup   = aws_athena_workgroup.this.name
  database    = each.value.database
  query       = each.value.query
  description = each.value.description
}
