data "aws_region" "current" {
  count = var.dashboard_name == null ? 0 : 1
}

locals {
  dashboard_region = var.dashboard_name == null ? null : data.aws_region.current[0].region

  dashboard_ecs_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 8
      height = 6
      properties = {
        title   = "${var.service_name} CPU and memory utilization"
        region  = local.dashboard_region
        view    = "timeSeries"
        stacked = false
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average" }],
          ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 8
      y      = 0
      width  = 8
      height = 6
      properties = {
        title   = "${var.service_name} desired and running tasks"
        region  = local.dashboard_region
        view    = "timeSeries"
        stacked = false
        metrics = [
          ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average" }],
          ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { stat = "Average" }],
        ]
      }
    },
  ]

  dashboard_alb_widgets = local.lb == null ? [] : [
    {
      type   = "metric"
      x      = 16
      y      = 0
      width  = 8
      height = 6
      properties = {
        title   = "${var.service_name} target requests and errors"
        region  = local.dashboard_region
        view    = "timeSeries"
        stacked = false
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "Sum" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "Sum" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "Sum" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 8
      height = 6
      properties = {
        title   = "${var.service_name} target hosts and p95 response time"
        region  = local.dashboard_region
        view    = "timeSeries"
        stacked = false
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "Minimum" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "Maximum" }],
          ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", local.lb.target_group_arn_suffix, "LoadBalancer", local.lb.alb_arn_suffix, { stat = "p95" }],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  count = var.dashboard_name == null ? 0 : 1

  dashboard_name = var.dashboard_name
  dashboard_body = jsonencode({ widgets = concat(local.dashboard_ecs_widgets, local.dashboard_alb_widgets) })
}
