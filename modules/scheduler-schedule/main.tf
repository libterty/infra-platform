resource "aws_scheduler_schedule_group" "this" {
  count = var.group_name == null ? 0 : 1

  name = var.group_name
  tags = merge(var.tags, { Name = var.group_name })
}

resource "aws_scheduler_schedule" "this" {
  for_each = var.schedules

  name                         = each.key
  group_name                   = var.group_name == null ? "default" : aws_scheduler_schedule_group.this[0].name
  schedule_expression          = each.value.expression
  schedule_expression_timezone = each.value.timezone
  state                        = each.value.state
  kms_key_arn                  = var.kms_key_arn

  flexible_time_window {
    mode                      = each.value.flexible_window_minutes == null ? "OFF" : "FLEXIBLE"
    maximum_window_in_minutes = each.value.flexible_window_minutes
  }

  target {
    arn      = each.value.target.arn
    role_arn = each.value.target.role_arn
    input    = each.value.target.input

    dynamic "sagemaker_pipeline_parameters" {
      for_each = each.value.target.sagemaker_pipeline_parameters == null ? [] : [each.value.target.sagemaker_pipeline_parameters]
      content {
        dynamic "pipeline_parameter" {
          for_each = sagemaker_pipeline_parameters.value
          content {
            name  = pipeline_parameter.key
            value = pipeline_parameter.value
          }
        }
      }
    }

    dynamic "dead_letter_config" {
      for_each = each.value.target.dead_letter_arn == null ? [] : [each.value.target.dead_letter_arn]
      content {
        arn = dead_letter_config.value
      }
    }

    dynamic "retry_policy" {
      for_each = each.value.target.retry == null ? [] : [each.value.target.retry]
      content {
        maximum_event_age_in_seconds = retry_policy.value.maximum_event_age_seconds
        maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
      }
    }
  }
}
