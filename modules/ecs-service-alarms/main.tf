locals {
  lb = var.load_balancer
  cfg = {
    ecs       = var.alarm_config.ecs
    container = var.alarm_config.container
    alb       = var.alarm_config.alb
  }

  service_dims = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }

  # Placeholder suffixes keep the object type fixed when load_balancer is null; those alarms are filtered out below.
  tg_dims = {
    LoadBalancer = local.lb == null ? "" : local.lb.alb_arn_suffix
    TargetGroup  = local.lb == null ? "" : local.lb.target_group_arn_suffix
  }

  alarm_defs = {
    cpu_high = {
      description         = "CPUUtilization >= ${local.cfg.ecs.cpu_threshold}% for 5 minutes"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = null
      threshold           = local.cfg.ecs.cpu_threshold
      treat_missing_data  = "missing"
      metric              = { namespace = "AWS/ECS", name = "CPUUtilization", period = 300, statistic = "Average", extended_statistic = null, dimensions = local.service_dims }
      queries             = []
    }
    memory_high = {
      description         = "MemoryUtilization >= ${local.cfg.ecs.memory_threshold}% for 5 minutes"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = null
      threshold           = local.cfg.ecs.memory_threshold
      treat_missing_data  = "missing"
      metric              = { namespace = "AWS/ECS", name = "MemoryUtilization", period = 300, statistic = "Average", extended_statistic = null, dimensions = local.service_dims }
      queries             = []
    }
    cpu_missing = {
      description         = "Service stopped reporting CPUUtilization for 2 consecutive periods"
      comparison_operator = "LessThanThreshold"
      evaluation_periods  = 2
      datapoints_to_alarm = null
      threshold           = 0
      treat_missing_data  = "breaching"
      metric              = { namespace = "AWS/ECS", name = "CPUUtilization", period = 60, statistic = "Average", extended_statistic = null, dimensions = local.service_dims }
      queries             = []
    }
    memory_missing = {
      description         = "Service stopped reporting MemoryUtilization for 2 consecutive periods"
      comparison_operator = "LessThanThreshold"
      evaluation_periods  = 2
      datapoints_to_alarm = null
      threshold           = 0
      treat_missing_data  = "breaching"
      metric              = { namespace = "AWS/ECS", name = "MemoryUtilization", period = 60, statistic = "Average", extended_statistic = null, dimensions = local.service_dims }
      queries             = []
    }
    tasks_below_desired = {
      description         = "RunningTaskCount < DesiredTaskCount for 3 of 5 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      threshold           = 0
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "deficit", expression = "desired - running", label = "Desired - Running", return_data = true, metric = null },
        { id = "running", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "RunningTaskCount", period = 60, stat = "Average", dimensions = local.service_dims } },
        { id = "desired", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "DesiredTaskCount", period = 60, stat = "Average", dimensions = local.service_dims } },
      ]
    }
    cpu_throttling = {
      description         = "CpuUtilized / CpuReserved > ${local.cfg.container.cpu_throttling_threshold} for 2 of 3 periods"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      threshold           = local.cfg.container.cpu_throttling_threshold
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "ratio", expression = "utilized / reserved", label = "CPU utilization ratio", return_data = true, metric = null },
        { id = "utilized", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "CpuUtilized", period = 300, stat = "Average", dimensions = local.service_dims } },
        { id = "reserved", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "CpuReserved", period = 300, stat = "Average", dimensions = local.service_dims } },
      ]
    }
    memory_pressure = {
      description         = "MemoryUtilized / MemoryReserved > ${local.cfg.container.memory_pressure_threshold} for 2 of 3 periods"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      threshold           = local.cfg.container.memory_pressure_threshold
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "ratio", expression = "utilized / reserved", label = "Memory utilization ratio", return_data = true, metric = null },
        { id = "utilized", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "MemoryUtilized", period = 300, stat = "Average", dimensions = local.service_dims } },
        { id = "reserved", expression = null, label = null, return_data = false, metric = { namespace = "ECS/ContainerInsights", name = "MemoryReserved", period = 300, stat = "Average", dimensions = local.service_dims } },
      ]
    }
    at_max_capacity = {
      description         = "RunningTaskCount reached max_capacity (${coalesce(var.max_capacity, 0)}) for 5 minutes"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 5
      datapoints_to_alarm = null
      threshold           = coalesce(var.max_capacity, 0)
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "ECS/ContainerInsights", name = "RunningTaskCount", period = 60, statistic = "Maximum", extended_statistic = null, dimensions = local.service_dims }
      queries             = []
    }
    target_5xx_ratio = {
      description         = "Target 5xx / RequestCount > ${local.cfg.alb.target_5xx_ratio_threshold}"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = null
      threshold           = local.cfg.alb.target_5xx_ratio_threshold
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "ratio", expression = "errors / requests", label = "Target 5xx ratio", return_data = true, metric = null },
        { id = "errors", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "HTTPCode_Target_5XX_Count", period = 300, stat = "Sum", dimensions = local.tg_dims } },
        { id = "requests", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "RequestCount", period = 300, stat = "Sum", dimensions = local.tg_dims } },
      ]
    }
    target_4xx_ratio = {
      description         = "Target 4xx / RequestCount > ${local.cfg.alb.target_4xx_ratio_threshold} for 2 of 3 periods"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      threshold           = local.cfg.alb.target_4xx_ratio_threshold
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "ratio", expression = "errors / requests", label = "Target 4xx ratio", return_data = true, metric = null },
        { id = "errors", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "HTTPCode_Target_4XX_Count", period = 300, stat = "Sum", dimensions = local.tg_dims } },
        { id = "requests", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "RequestCount", period = 300, stat = "Sum", dimensions = local.tg_dims } },
      ]
    }
    latency_p95 = {
      description         = "TargetResponseTime p95 > ${local.cfg.alb.latency_p95_threshold_ms} ms for 3 periods"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = null
      threshold           = local.cfg.alb.latency_p95_threshold_ms / 1000
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "AWS/ApplicationELB", name = "TargetResponseTime", period = 300, statistic = null, extended_statistic = "p95", dimensions = local.tg_dims }
      queries             = []
    }
    unhealthy_hosts = {
      description         = "HealthyHostCount < ${local.cfg.alb.healthy_host_min} for 2 of 3 minutes"
      comparison_operator = "LessThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      threshold           = local.cfg.alb.healthy_host_min
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "AWS/ApplicationELB", name = "HealthyHostCount", period = 60, statistic = "Minimum", extended_statistic = null, dimensions = local.tg_dims }
      queries             = []
    }
    target_connection_errors = {
      description         = "TargetConnectionErrorCount > 0 (the ALB cannot connect to targets)"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = null
      threshold           = 0
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "AWS/ApplicationELB", name = "TargetConnectionErrorCount", period = 300, statistic = "Sum", extended_statistic = null, dimensions = local.tg_dims }
      queries             = []
    }
  }

  alb_alarm_keys = ["target_5xx_ratio", "target_4xx_ratio", "latency_p95", "unhealthy_hosts", "target_connection_errors"]

  alarms = {
    for k, v in local.alarm_defs : k => v
    if(k == "at_max_capacity" ? var.max_capacity != null : (contains(local.alb_alarm_keys, k) ? local.lb != null : true))
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = var.sns_topic_arns
  ok_actions          = var.sns_topic_arns

  metric_name        = each.value.metric == null ? null : each.value.metric.name
  namespace          = each.value.metric == null ? null : each.value.metric.namespace
  period             = each.value.metric == null ? null : each.value.metric.period
  statistic          = each.value.metric == null ? null : each.value.metric.statistic
  extended_statistic = each.value.metric == null ? null : each.value.metric.extended_statistic
  dimensions         = each.value.metric == null ? null : each.value.metric.dimensions

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
          metric_name = metric.value.name
          namespace   = metric.value.namespace
          period      = metric.value.period
          stat        = metric.value.stat
          dimensions  = metric.value.dimensions
        }
      }
    }
  }

  tags = var.tags
}
