locals {
  lb  = var.load_balancer
  alb = var.alarm_config.alb

  pod_dims = {
    ClusterName = var.cluster_name
    Namespace   = var.namespace
    PodName     = var.workload_name
  }

  container_dims = merge(local.pod_dims, { ContainerName = var.container_name })

  # Placeholder suffixes keep the object type fixed when load_balancer is null; those alarms are filtered out below.
  tg_dims = {
    LoadBalancer = local.lb == null ? "" : local.lb.alb_arn_suffix
    TargetGroup  = local.lb == null ? "" : local.lb.target_group_arn_suffix
  }

  alarm_defs = {
    replicas_below_desired = {
      description         = "replicas_desired - replicas_ready > 0 for 10 consecutive minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 10
      datapoints_to_alarm = 10
      threshold           = 0
      treat_missing_data  = "breaching"
      metric              = null
      queries = [
        { id = "deficit", expression = "desired - ready", label = "Desired - Ready", return_data = true, metric = null },
        { id = "ready", expression = null, label = null, return_data = false, metric = { namespace = "ContainerInsights", name = "replicas_ready", period = 60, stat = "Average", dimensions = local.pod_dims } },
        { id = "desired", expression = null, label = null, return_data = false, metric = { namespace = "ContainerInsights", name = "replicas_desired", period = 60, stat = "Average", dimensions = local.pod_dims } },
      ]
    }
    crash_loop = {
      description         = "Container in CrashLoopBackOff for 3 of 5 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      threshold           = 0
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "ContainerInsights", name = "pod_container_status_waiting_reason_crash_loop_back_off", period = 60, statistic = "Maximum", extended_statistic = null, dimensions = local.pod_dims }
      queries             = []
    }
    restarts = {
      description         = "Container restarts in 5 minutes > ${var.restart_threshold}"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      threshold           = var.restart_threshold
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "ContainerInsights", name = "pod_number_of_container_restarts", period = 300, statistic = "Sum", extended_statistic = null, dimensions = local.pod_dims }
      queries             = []
    }
    pending = {
      description         = "Pod Pending for 10 consecutive minutes"
      comparison_operator = "GreaterThanOrEqualToThreshold"
      evaluation_periods  = 10
      datapoints_to_alarm = 10
      threshold           = 1
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "ContainerInsights", name = "pod_status_pending", period = 60, statistic = "Maximum", extended_statistic = null, dimensions = local.pod_dims }
      queries             = []
    }
    oom_killed = {
      description         = "Container terminated by OOMKilled in the last 5 minutes"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = 1
      threshold           = 0
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "ContainerInsights", name = "pod_container_status_terminated_reason_oom_killed", period = 300, statistic = "Sum", extended_statistic = null, dimensions = local.container_dims }
      queries             = []
    }
    target_5xx_ratio = {
      description         = "Target 5xx / RequestCount > ${local.alb.target_5xx_ratio_threshold}"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      datapoints_to_alarm = null
      threshold           = local.alb.target_5xx_ratio_threshold
      treat_missing_data  = "notBreaching"
      metric              = null
      queries = [
        { id = "ratio", expression = "errors / requests", label = "Target 5xx ratio", return_data = true, metric = null },
        { id = "errors", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "HTTPCode_Target_5XX_Count", period = 300, stat = "Sum", dimensions = local.tg_dims } },
        { id = "requests", expression = null, label = null, return_data = false, metric = { namespace = "AWS/ApplicationELB", name = "RequestCount", period = 300, stat = "Sum", dimensions = local.tg_dims } },
      ]
    }
    latency_p95 = {
      description         = "TargetResponseTime p95 > ${local.alb.latency_p95_threshold_ms} ms for 3 periods"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = null
      threshold           = local.alb.latency_p95_threshold_ms / 1000
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "AWS/ApplicationELB", name = "TargetResponseTime", period = 300, statistic = null, extended_statistic = "p95", dimensions = local.tg_dims }
      queries             = []
    }
    unhealthy_hosts = {
      description         = "HealthyHostCount < ${local.alb.healthy_host_min} for 2 of 3 minutes"
      comparison_operator = "LessThanThreshold"
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      threshold           = local.alb.healthy_host_min
      treat_missing_data  = "notBreaching"
      metric              = { namespace = "AWS/ApplicationELB", name = "HealthyHostCount", period = 60, statistic = "Minimum", extended_statistic = null, dimensions = local.tg_dims }
      queries             = []
    }
  }

  alb_alarm_keys = ["target_5xx_ratio", "latency_p95", "unhealthy_hosts"]

  alarms = {
    for k, v in local.alarm_defs : k => v
    if local.lb != null || !contains(local.alb_alarm_keys, k)
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
