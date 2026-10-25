resource "aws_cloudwatch_event_rule" "this" {
  name                = var.name
  event_bus_name      = var.event_bus_name
  event_pattern       = var.event_pattern == null ? null : jsonencode(var.event_pattern)
  schedule_expression = var.schedule_expression
  state               = var.state

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = var.targets

  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = var.event_bus_name
  target_id      = each.key
  arn            = each.value.arn
  role_arn       = each.value.role_arn

  dynamic "input_transformer" {
    for_each = each.value.input_transformer == null ? [] : [each.value.input_transformer]
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_arn == null ? [] : [each.value.dead_letter_arn]
    content {
      arn = dead_letter_config.value
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry == null ? [] : [each.value.retry]
    content {
      maximum_event_age_in_seconds = retry_policy.value.maximum_event_age_seconds
      maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
    }
  }

  dynamic "sqs_target" {
    for_each = each.value.sqs_message_group_id == null ? [] : [each.value.sqs_message_group_id]
    content {
      message_group_id = sqs_target.value
    }
  }
}
