locals {
  names = { for k in keys(var.alarms) : k => "${var.name_prefix}-${replace(k, "_", "-")}" }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = var.alarms

  alarm_name          = local.names[each.key]
  alarm_description   = each.value.description
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data

  # Single metric form; all null when queries is used.
  namespace   = each.value.metric == null ? null : each.value.metric.namespace
  metric_name = each.value.metric == null ? null : each.value.metric.metric_name
  dimensions  = each.value.metric == null ? null : each.value.metric.dimensions
  statistic   = each.value.metric == null ? null : each.value.metric.statistic
  period      = each.value.metric == null ? null : each.value.metric.period

  # Metric math form.
  dynamic "metric_query" {
    for_each = each.value.queries
    content {
      id          = metric_query.value.id
      expression  = metric_query.value.expression
      label       = metric_query.value.label
      return_data = metric_query.value.return_data

      dynamic "metric" {
        for_each = metric_query.value.metric == null ? [] : [metric_query.value.metric]
        content {
          namespace   = metric.value.namespace
          metric_name = metric.value.metric_name
          dimensions  = metric.value.dimensions
          stat        = metric.value.statistic
          period      = metric.value.period
        }
      }
    }
  }

  alarm_actions = var.sns_topic_arns
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = local.names[each.key] })
}
