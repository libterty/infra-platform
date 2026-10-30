locals {
  autoscaling_policy  = var.autoscaling == null ? null : var.autoscaling.policy
  use_target_tracking = local.autoscaling_policy == "target_tracking"
  use_step            = local.autoscaling_policy == "step"
  use_requests        = local.use_target_tracking && try(var.autoscaling.target_tracking.requests_per_target, null) != null

  custom_step_policies = var.autoscaling == null ? {} : var.autoscaling.step_policies
  scheduled_actions    = var.autoscaling == null ? {} : var.autoscaling.scheduled_actions

  step_groups = local.use_step ? {
    cpu_scale_out = {
      metric  = "CPUUtilization", comparison = "GreaterThanOrEqualToThreshold", threshold = var.autoscaling.step.cpu_scale_out_threshold
      periods = 1, cooldown = var.autoscaling.step.scale_out_cooldown, out = true
    }
    cpu_scale_in = {
      metric  = "CPUUtilization", comparison = "LessThanThreshold", threshold = var.autoscaling.step.cpu_scale_in_threshold
      periods = 5, cooldown = var.autoscaling.step.scale_in_cooldown, out = false
    }
    memory_scale_out = {
      metric  = "MemoryUtilization", comparison = "GreaterThanOrEqualToThreshold", threshold = var.autoscaling.step.memory_scale_out_threshold
      periods = 1, cooldown = var.autoscaling.step.scale_out_cooldown, out = true
    }
    memory_scale_in = {
      metric  = "MemoryUtilization", comparison = "LessThanOrEqualToThreshold", threshold = var.autoscaling.step.memory_scale_in_threshold
      periods = 5, cooldown = var.autoscaling.step.scale_in_cooldown, out = false
    }
  } : {}
}

# Always created, even without autoscaling, because the service ignores desired_count.
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${local.cluster_name}/${local.service.name}"
  min_capacity       = var.autoscaling == null ? var.desired_count : var.autoscaling.min_capacity
  max_capacity       = var.autoscaling == null ? var.desired_count : var.autoscaling.max_capacity

  tags = local.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  count = local.use_target_tracking ? 1 : 0

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling.target_tracking.cpu_percent
    scale_in_cooldown  = var.autoscaling.target_tracking.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.target_tracking.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count = local.use_requests ? 1 : 0

  name               = "${var.name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${var.load_balancer.alb_arn_suffix}/${local.target_group_arn_suffix}"
    }
    target_value       = var.autoscaling.target_tracking.requests_per_target
    scale_in_cooldown  = var.autoscaling.target_tracking.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.target_tracking.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "step" {
  for_each = local.step_groups

  name               = "${var.name}-${replace(each.key, "_", "-")}"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.cooldown
    metric_aggregation_type = "Average"

    dynamic "step_adjustment" {
      for_each = each.value.out ? [1, 2, 3] : []
      content {
        metric_interval_lower_bound = (step_adjustment.value - 1) * var.autoscaling.step.scale_out_step_size
        metric_interval_upper_bound = step_adjustment.value == 3 ? null : step_adjustment.value * var.autoscaling.step.scale_out_step_size
        scaling_adjustment          = step_adjustment.value
      }
    }

    dynamic "step_adjustment" {
      for_each = each.value.out ? [] : [1]
      content {
        metric_interval_upper_bound = 0
        scaling_adjustment          = -1
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "scaling" {
  for_each = local.step_groups

  alarm_name          = "${var.name}-${replace(each.key, "_", "-")}"
  alarm_description   = "${each.value.metric} ${each.value.comparison} ${each.value.threshold} on ${var.name}; triggers ${each.key}"
  comparison_operator = each.value.comparison
  metric_name         = each.value.metric
  namespace           = "AWS/ECS"
  period              = 60
  evaluation_periods  = each.value.periods
  statistic           = "Average"
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.step[each.key].arn]

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = local.service.name
  }

  tags = local.tags
}

# Names carry a "step-" infix so a custom key can never clash with a built-in policy or alarm name.
resource "aws_appautoscaling_policy" "custom_step" {
  for_each = local.custom_step_policies

  name               = "${var.name}-step-${replace(each.key, "_", "-")}"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = each.value.cooldown
    metric_aggregation_type = "Average"

    dynamic "step_adjustment" {
      for_each = each.value.adjustments
      content {
        metric_interval_lower_bound = step_adjustment.value.lower
        metric_interval_upper_bound = step_adjustment.value.upper
        scaling_adjustment          = step_adjustment.value.change
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "custom_step" {
  for_each = local.custom_step_policies

  alarm_name          = "${var.name}-step-${replace(each.key, "_", "-")}"
  alarm_description   = "Custom step scaling trigger ${each.key} on ${var.name}"
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = [aws_appautoscaling_policy.custom_step[each.key].arn]

  # Single metric form; null when the policy uses metric math queries.
  namespace   = each.value.metric == null ? null : each.value.metric.namespace
  metric_name = each.value.metric == null ? null : each.value.metric.metric_name
  period      = each.value.metric == null ? null : each.value.metric.period
  statistic   = each.value.metric == null ? null : each.value.metric.statistic
  dimensions  = each.value.metric == null ? null : each.value.metric.dimensions

  dynamic "metric_query" {
    for_each = each.value.queries == null ? [] : each.value.queries
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
          period      = metric.value.period
          stat        = metric.value.stat
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = local.scheduled_actions

  name               = "${var.name}-${replace(each.key, "_", "-")}"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id
  schedule           = each.value.schedule
  timezone           = each.value.timezone

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}
