# All three resources are account-and-region singletons without a name or ID; the provider's delete is a no-op
# for each of them, so removing an input leaves the last applied setting in AWS.

resource "aws_iot_indexing_configuration" "this" {
  count = var.indexing == null ? 0 : 1

  thing_indexing_configuration {
    thing_indexing_mode              = var.indexing.thing_indexing_mode
    thing_connectivity_indexing_mode = var.indexing.thing_connectivity_indexing_mode
    named_shadow_indexing_mode       = var.indexing.named_shadow_indexing_mode
    device_defender_indexing_mode    = var.indexing.device_defender_indexing_mode

    dynamic "custom_field" {
      for_each = var.indexing.custom_fields
      content {
        name = custom_field.key
        type = custom_field.value
      }
    }
  }

  thing_group_indexing_configuration {
    thing_group_indexing_mode = var.indexing.thing_group_indexing_mode
  }
}

resource "aws_iot_logging_options" "this" {
  count = var.logging == null ? 0 : 1

  role_arn          = var.logging.role_arn
  default_log_level = var.logging.default_log_level
  disable_all_logs  = false
}

resource "aws_iot_event_configurations" "this" {
  count = var.event_configurations == null ? 0 : 1

  event_configurations = var.event_configurations
}
