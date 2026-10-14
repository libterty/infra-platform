locals {
  autoscaling_policy  = var.autoscaling == null ? null : var.autoscaling.policy
  use_target_tracking = local.autoscaling_policy == "target_tracking"
  use_step            = local.autoscaling_policy == "step"
  use_requests        = local.use_target_tracking && try(var.autoscaling.target_tracking.requests_per_target, null) != null

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
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.this.name}"
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
    ServiceName = aws_ecs_service.this.name
  }

  tags = local.tags
}
