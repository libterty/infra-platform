locals {
  use_exclusions = length(var.recording.exclusion_types) > 0
}

resource "aws_config_configuration_recorder" "this" {
  name     = var.name
  region   = var.region
  role_arn = var.role_arn

  recording_group {
    all_supported                 = !local.use_exclusions
    include_global_resource_types = var.recording.include_global_resource_types

    recording_strategy {
      use_only = local.use_exclusions ? "EXCLUSION_BY_RESOURCE_TYPES" : "ALL_SUPPORTED_RESOURCE_TYPES"
    }

    dynamic "exclusion_by_resource_types" {
      for_each = local.use_exclusions ? [1] : []
      content {
        resource_types = var.recording.exclusion_types
      }
    }
  }

  recording_mode {
    recording_frequency = var.recording_frequency
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = var.name
  region         = var.region
  s3_bucket_name = var.s3_bucket_name
  s3_key_prefix  = var.s3_key_prefix
  s3_kms_key_arn = var.s3_kms_key_arn
  sns_topic_arn  = var.sns_topic_arn

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_frequency
  }

  # PutDeliveryChannel fails when the region has no recorder yet.
  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  region     = var.region
  is_enabled = true

  # StartConfigurationRecorder fails without a delivery channel.
  depends_on = [aws_config_delivery_channel.this]
}

resource "aws_config_retention_configuration" "this" {
  region                   = var.region
  retention_period_in_days = var.retention_days
}

resource "aws_config_config_rule" "this" {
  for_each = var.managed_rules

  name             = lower(replace(each.key, "_", "-"))
  region           = var.region
  input_parameters = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null

  source {
    owner             = "AWS"
    source_identifier = each.key
  }

  dynamic "scope" {
    for_each = length(each.value.scope_resource_types) > 0 ? [1] : []
    content {
      compliance_resource_types = each.value.scope_resource_types
    }
  }

  tags = merge(var.tags, { Name = lower(replace(each.key, "_", "-")) })

  # PutConfigRule fails when the region has no recorder yet.
  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_aggregator" "this" {
  count = var.aggregator != null ? 1 : 0

  name   = var.aggregator.name
  region = var.region

  dynamic "account_aggregation_source" {
    for_each = length(var.aggregator.account_ids) > 0 ? [1] : []
    content {
      account_ids = var.aggregator.account_ids
      all_regions = length(var.aggregator.regions) == 0
      regions     = length(var.aggregator.regions) > 0 ? var.aggregator.regions : null
    }
  }

  dynamic "organization_aggregation_source" {
    for_each = var.aggregator.organization_role_arn != null ? [1] : []
    content {
      role_arn    = var.aggregator.organization_role_arn
      all_regions = length(var.aggregator.regions) == 0
      regions     = length(var.aggregator.regions) > 0 ? var.aggregator.regions : null
    }
  }

  tags = merge(var.tags, { Name = var.aggregator.name })
}
