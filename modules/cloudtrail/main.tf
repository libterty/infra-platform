resource "aws_cloudtrail" "this" {
  name           = var.name
  region         = var.region
  s3_bucket_name = var.s3_bucket_name
  s3_key_prefix  = var.s3_key_prefix
  kms_key_id     = var.kms_key_arn

  is_multi_region_trail         = var.is_multi_region_trail
  is_organization_trail         = var.is_organization_trail
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  cloud_watch_logs_group_arn = try(var.cloudwatch_logs.log_group_arn, null)
  cloud_watch_logs_role_arn  = try(var.cloudwatch_logs.role_arn, null)

  dynamic "advanced_event_selector" {
    for_each = coalesce(var.advanced_event_selectors, [])
    content {
      name = advanced_event_selector.value.name

      dynamic "field_selector" {
        for_each = advanced_event_selector.value.field_selectors
        content {
          field           = field_selector.value.field
          equals          = field_selector.value.equals
          not_equals      = field_selector.value.not_equals
          starts_with     = field_selector.value.starts_with
          not_starts_with = field_selector.value.not_starts_with
          ends_with       = field_selector.value.ends_with
          not_ends_with   = field_selector.value.not_ends_with
        }
      }
    }
  }

  dynamic "insight_selector" {
    for_each = toset(var.insight_types)
    content {
      insight_type = insight_selector.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
