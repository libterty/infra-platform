locals {
  # Alarm entries and metric-only entries share one filter shape; keys cannot overlap (see var.metrics).
  filters = merge(
    { for k, v in var.alarms : k => { pattern = v.pattern, metric_name = v.metric_name, metric_value = v.metric_value, default_value = v.default_value } },
    { for k, v in var.metrics : k => { pattern = v.pattern, metric_name = v.metric_name, metric_value = v.metric_value, default_value = v.default_value } },
  )
  names = { for k in keys(local.filters) : k => "${var.name_prefix}-${replace(k, "_", "-")}" }
}

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = local.filters

  name           = local.names[each.key]
  log_group_name = var.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric_name
    namespace     = var.namespace
    value         = each.value.metric_value
    default_value = tostring(each.value.default_value)
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = local.names[each.key]
  alarm_description   = each.value.description
  namespace           = var.namespace
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  treat_missing_data  = each.value.treat_missing_data

  alarm_actions = var.sns_topic_arns
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = local.names[each.key] })

  # The metric must exist before the alarm, otherwise the alarm starts in INSUFFICIENT_DATA.
  depends_on = [aws_cloudwatch_log_metric_filter.this]
}
