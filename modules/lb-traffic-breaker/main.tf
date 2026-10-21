data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  is_alb    = var.load_balancer_type == "application"
  namespace = local.is_alb ? "AWS/ApplicationELB" : "AWS/NetworkELB"

  # Defaults of the ALB-only settings; an NLB must not set them (see variables.tf), so they stay null there.
  alb_breakers = { for k, v in var.breakers : k => v if local.is_alb }
  error_rate_percent = {
    for k, v in local.alb_breakers : k => v.error_rate_percent == null ? 5 : v.error_rate_percent
  }
  min_requests = {
    for k, v in local.alb_breakers : k => v.min_requests == null ? 50 : v.min_requests
  }
  custom_breakers = { for k, v in var.breakers : k => v if v.custom_metric != null }

  # Every alarm of the module: "<breaker key>-<signal>" => { breaker key, alarm name }.
  # Names are built from inputs only (never from the alarm resources), so lambda_permissions can be
  # passed to the lambda-function that this module's lambda_function_arn comes from without a cycle.
  alarms = merge(
    { for k in keys(local.alb_breakers) : "${k}-error-rate" => { breaker = k, name = "${var.name}-${k}-error-rate" } },
    { for k in keys(var.breakers) : "${k}-healthy-hosts" => { breaker = k, name = "${var.name}-${k}-healthy-hosts" } },
    { for k in keys(local.custom_breakers) : "${k}-custom" => { breaker = k, name = "${var.name}-${k}-custom" } },
  )

  dimensions = {
    for k, v in var.breakers : k => {
      LoadBalancer = var.load_balancer_arn_suffix
      TargetGroup  = v.canary_target_group_arn_suffix
    }
  }

  # What the Lambda needs per breaker. null fields are dropped so the JSON has exactly one of listener_arn or rule_arn.
  targets = {
    for k, v in var.breakers : k => {
      for f, x in {
        listener_arn            = v.listener_arn
        rule_arn                = v.rule_arn
        stable_target_group_arn = v.stable_target_group_arn
      } : f => x if x != null
    }
  }

  # schema_version must match SUPPORTED_SCHEMA_VERSION in lambda/breaker.py.
  lambda_config = {
    schema_version = 1
    alarms         = { for a in local.alarms : a.name => local.targets[a.breaker] }
  }

  alarm_actions = concat([var.lambda_function_arn], var.sns_topic_arns)
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  for_each = local.alb_breakers

  alarm_name          = local.alarms["${each.key}-error-rate"].name
  alarm_description   = "More than ${local.error_rate_percent[each.key]} percent of the requests to ${each.value.canary_target_group_arn_suffix} returned 5xx (periods with fewer than ${local.min_requests[each.key]} requests are ignored). Trips breaker ${each.key}: the Lambda shifts traffic to the stable target group."
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.error_rate_percent[each.key]
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  # No requests means nothing is failing; do not trip on silence.
  treat_missing_data = "notBreaching"

  metric_query {
    id          = "errors"
    return_data = false

    metric {
      namespace   = local.namespace
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = each.value.period
      stat        = "Sum"
      dimensions  = local.dimensions[each.key]
    }
  }

  metric_query {
    id          = "requests"
    return_data = false

    metric {
      namespace   = local.namespace
      metric_name = "RequestCount"
      period      = each.value.period
      stat        = "Sum"
      dimensions  = local.dimensions[each.key]
    }
  }

  metric_query {
    id = "rate"
    # FILL turns "no 5xx datapoint" into 0; IF drops the percentage when there are too few requests to judge.
    expression  = "IF(requests >= ${local.min_requests[each.key]}, 100 * FILL(errors, 0) / requests, 0)"
    label       = "5xx percent"
    return_data = true
  }

  alarm_actions = local.alarm_actions
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = local.alarms["${each.key}-error-rate"].name })
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  for_each = var.breakers

  alarm_name          = local.alarms["${each.key}-healthy-hosts"].name
  alarm_description   = "HealthyHostCount of ${each.value.canary_target_group_arn_suffix} is below ${each.value.min_healthy_hosts}. Trips breaker ${each.key}: the Lambda shifts traffic to the stable target group."
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.min_healthy_hosts
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  # Missing data usually means the target group has no registered target or is not reporting: treat it as unhealthy.
  treat_missing_data = "breaching"

  namespace   = local.namespace
  metric_name = "HealthyHostCount"
  period      = each.value.period
  statistic   = "Minimum"
  dimensions  = local.dimensions[each.key]

  alarm_actions = local.alarm_actions
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = local.alarms["${each.key}-healthy-hosts"].name })
}

resource "aws_cloudwatch_metric_alarm" "custom" {
  for_each = local.custom_breakers

  alarm_name          = local.alarms["${each.key}-custom"].name
  alarm_description   = "Custom metric ${each.value.custom_metric.namespace}/${each.value.custom_metric.metric_name} crossed ${each.value.custom_metric.threshold}. Trips breaker ${each.key}: the Lambda shifts traffic to the stable target group."
  comparison_operator = each.value.custom_metric.comparison_operator
  threshold           = each.value.custom_metric.threshold
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  # An application that publishes nothing is not evidence of a problem; the healthy-hosts alarm covers a dead target group.
  treat_missing_data = "notBreaching"

  namespace   = each.value.custom_metric.namespace
  metric_name = each.value.custom_metric.metric_name
  period      = each.value.period
  statistic   = each.value.custom_metric.statistic
  dimensions  = each.value.custom_metric.dimensions

  alarm_actions = local.alarm_actions
  ok_actions    = var.sns_topic_arns

  tags = merge(var.tags, { Name = local.alarms["${each.key}-custom"].name })
}
