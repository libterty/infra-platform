mock_provider "aws" {}

variables {
  name           = "alpha-api"
  cluster_name   = "alpha-dev"
  namespace      = "alpha"
  workload_name  = "alpha-api"
  container_name = "api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "base_set_without_lb" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.this)) == toset(["replicas_below_desired", "crash_loop", "restarts", "pending", "oom_killed"])
    error_message = "Without load_balancer exactly the 5 workload alarms must exist"
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_name == "alpha-api-${k}"])
    error_message = "Alarm names must be <name>-<key>"
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "Every alarm must send alarm_actions and ok_actions to sns_topic_arns"
  }
}

run "replicas_below_desired" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["replicas_below_desired"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["replicas_below_desired"].threshold == 0 &&
      aws_cloudwatch_metric_alarm.this["replicas_below_desired"].evaluation_periods == 10 &&
      aws_cloudwatch_metric_alarm.this["replicas_below_desired"].datapoints_to_alarm == 10 &&
      aws_cloudwatch_metric_alarm.this["replicas_below_desired"].treat_missing_data == "breaching"
    )
    error_message = "replicas_below_desired: > 0, 10 of 10, breaching"
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.this["replicas_below_desired"].metric_query) == 3 &&
      one([for q in aws_cloudwatch_metric_alarm.this["replicas_below_desired"].metric_query : q.expression if q.return_data]) == "desired - ready"
    )
    error_message = "replicas_below_desired must be metric math desired - ready"
  }

  assert {
    condition = alltrue([
      for q in aws_cloudwatch_metric_alarm.this["replicas_below_desired"].metric_query : (
        q.metric[0].namespace == "ContainerInsights" &&
        q.metric[0].period == 60 &&
        q.metric[0].stat == "Average" &&
        q.metric[0].dimensions == tomap({ ClusterName = "alpha-dev", Namespace = "alpha", PodName = "alpha-api" })
      ) if !q.return_data
    ])
    error_message = "Both inputs: ContainerInsights, Average, 60s, dims ClusterName/Namespace/PodName"
  }

  assert {
    condition = (
      one([for q in aws_cloudwatch_metric_alarm.this["replicas_below_desired"].metric_query : q.metric[0].metric_name if q.id == "desired"]) == "replicas_desired" &&
      one([for q in aws_cloudwatch_metric_alarm.this["replicas_below_desired"].metric_query : q.metric[0].metric_name if q.id == "ready"]) == "replicas_ready"
    )
    error_message = "Inputs must be replicas_desired and replicas_ready"
  }
}

run "crash_loop" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["crash_loop"].namespace == "ContainerInsights" &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].metric_name == "pod_container_status_waiting_reason_crash_loop_back_off" &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].dimensions == tomap({ ClusterName = "alpha-dev", Namespace = "alpha", PodName = "alpha-api" }) &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].statistic == "Maximum" &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].period == 60 &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].datapoints_to_alarm == 3 &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].threshold == 0 &&
      aws_cloudwatch_metric_alarm.this["crash_loop"].treat_missing_data == "notBreaching"
    )
    error_message = "crash_loop: Maximum, 60s, 3 of 5, > 0, notBreaching"
  }
}

run "restarts_default" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["restarts"].namespace == "ContainerInsights" &&
      aws_cloudwatch_metric_alarm.this["restarts"].metric_name == "pod_number_of_container_restarts" &&
      aws_cloudwatch_metric_alarm.this["restarts"].dimensions == tomap({ ClusterName = "alpha-dev", Namespace = "alpha", PodName = "alpha-api" }) &&
      aws_cloudwatch_metric_alarm.this["restarts"].statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.this["restarts"].period == 300 &&
      aws_cloudwatch_metric_alarm.this["restarts"].evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.this["restarts"].datapoints_to_alarm == 1 &&
      aws_cloudwatch_metric_alarm.this["restarts"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["restarts"].threshold == 0 &&
      aws_cloudwatch_metric_alarm.this["restarts"].treat_missing_data == "notBreaching"
    )
    error_message = "restarts: Sum, 300s, 1 of 1, > 0 by default, notBreaching"
  }
}

run "restarts_custom_threshold" {
  command = plan

  variables {
    restart_threshold = 3
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["restarts"].threshold == 3
    error_message = "restart_threshold must drive the restarts threshold"
  }
}

run "pending" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["pending"].namespace == "ContainerInsights" &&
      aws_cloudwatch_metric_alarm.this["pending"].metric_name == "pod_status_pending" &&
      aws_cloudwatch_metric_alarm.this["pending"].dimensions == tomap({ ClusterName = "alpha-dev", Namespace = "alpha", PodName = "alpha-api" }) &&
      aws_cloudwatch_metric_alarm.this["pending"].statistic == "Maximum" &&
      aws_cloudwatch_metric_alarm.this["pending"].period == 60 &&
      aws_cloudwatch_metric_alarm.this["pending"].evaluation_periods == 10 &&
      aws_cloudwatch_metric_alarm.this["pending"].datapoints_to_alarm == 10 &&
      aws_cloudwatch_metric_alarm.this["pending"].comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.this["pending"].threshold == 1 &&
      aws_cloudwatch_metric_alarm.this["pending"].treat_missing_data == "notBreaching"
    )
    error_message = "pending: Maximum, 60s, 10 of 10, >= 1, notBreaching"
  }
}

run "oom_killed" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["oom_killed"].namespace == "ContainerInsights" &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].metric_name == "pod_container_status_terminated_reason_oom_killed" &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].dimensions == tomap({ ClusterName = "alpha-dev", Namespace = "alpha", PodName = "alpha-api", ContainerName = "api" }) &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].period == 300 &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].datapoints_to_alarm == 1 &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].threshold == 0 &&
      aws_cloudwatch_metric_alarm.this["oom_killed"].treat_missing_data == "notBreaching"
    )
    error_message = "oom_killed: Sum, 300s, 1 of 1, > 0, notBreaching, with ContainerName dim"
  }
}

run "alb_alarms_with_load_balancer" {
  command = plan

  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 8
    error_message = "With load_balancer the 3 ALB alarms are added to the 5 workload alarms"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].threshold == 0.01 &&
      aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].treat_missing_data == "notBreaching" &&
      one([for q in aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].metric_query : q.expression if q.return_data]) == "errors / requests" &&
      one([for q in aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].metric_query : q.metric[0].metric_name if q.id == "errors"]) == "HTTPCode_Target_5XX_Count" &&
      one([for q in aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].metric_query : q.metric[0].metric_name if q.id == "requests"]) == "RequestCount" &&
      alltrue([
        for q in aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].metric_query : (
          q.metric[0].namespace == "AWS/ApplicationELB" && q.metric[0].period == 300 && q.metric[0].stat == "Sum" &&
          q.metric[0].dimensions == tomap({ LoadBalancer = "app/alpha/abc", TargetGroup = "targetgroup/alpha-api/def" })
        ) if !q.return_data
      ])
    )
    error_message = "target_5xx_ratio: Sum 5xx / RequestCount > 0.01, 300s x 1, TargetGroup/LoadBalancer dims"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["latency_p95"].namespace == "AWS/ApplicationELB" &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].metric_name == "TargetResponseTime" &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].extended_statistic == "p95" &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].period == 300 &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].threshold == 0.8 &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].treat_missing_data == "notBreaching" &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].dimensions == tomap({ LoadBalancer = "app/alpha/abc", TargetGroup = "targetgroup/alpha-api/def" })
    )
    error_message = "latency_p95: p95 TargetResponseTime > 0.8 s, 300s x 3"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].namespace == "AWS/ApplicationELB" &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].metric_name == "HealthyHostCount" &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].statistic == "Minimum" &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].period == 60 &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].datapoints_to_alarm == 2 &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].comparison_operator == "LessThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].threshold == 1 &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].treat_missing_data == "notBreaching" &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].dimensions == tomap({ LoadBalancer = "app/alpha/abc", TargetGroup = "targetgroup/alpha-api/def" })
    )
    error_message = "unhealthy_hosts: Minimum HealthyHostCount < 1, 60s, 2 of 3"
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "ALB alarms must also notify sns_topic_arns"
  }
}

run "alarm_config_overrides_alb_thresholds" {
  command = plan

  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
    alarm_config = {
      alb = { target_5xx_ratio_threshold = 0.05, latency_p95_threshold_ms = 1500, healthy_host_min = 2 }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].threshold == 0.05 &&
      aws_cloudwatch_metric_alarm.this["latency_p95"].threshold == 1.5 &&
      aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].threshold == 2
    )
    error_message = "alarm_config.alb must override the ALB thresholds (latency in ms, alarm in seconds)"
  }
}

run "tags_are_applied" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.tags["Project"] == "alpha"])
    error_message = "tags must reach every alarm"
  }
}
