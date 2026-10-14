mock_provider "aws" {}

variables {
  name           = "alpha-api"
  cluster_name   = "alpha-dev"
  service_name   = "alpha-api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "every_alarm_notifies_both_ways" {
  command = plan

  variables {
    max_capacity  = 6
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 13
    error_message = "With max_capacity and a load balancer all 13 alarms must exist"
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(var.sns_topic_arns) && a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "Every alarm must send alarm_actions and ok_actions to sns_topic_arns"
  }
}

run "base_set_without_lb_or_max" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.this)) == toset(["cpu_high", "memory_high", "cpu_missing", "memory_missing", "tasks_below_desired", "cpu_throttling", "memory_pressure"])
    error_message = "Without load_balancer and max_capacity exactly the 7 service alarms must exist"
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_name == "alpha-api-${k}"])
    error_message = "Alarm names must be <name>-<key>"
  }
}

run "service_alarm_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].threshold == 80 && aws_cloudwatch_metric_alarm.this["cpu_high"].period == 300 && aws_cloudwatch_metric_alarm.this["cpu_high"].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.this["cpu_high"].metric_name == "CPUUtilization" && aws_cloudwatch_metric_alarm.this["cpu_high"].treat_missing_data == "missing"
    error_message = "cpu_high default: CPUUtilization >= 80, 300s x 1, missing"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["memory_high"].threshold == 80 && aws_cloudwatch_metric_alarm.this["memory_high"].metric_name == "MemoryUtilization" && aws_cloudwatch_metric_alarm.this["memory_high"].period == 300
    error_message = "memory_high default: MemoryUtilization >= 80, 300s"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "cpu_high must use >="
  }

  assert {
    condition     = alltrue([for k in ["cpu_missing", "memory_missing"] : aws_cloudwatch_metric_alarm.this[k].treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.this[k].period == 60 && aws_cloudwatch_metric_alarm.this[k].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.this[k].threshold == 0 && aws_cloudwatch_metric_alarm.this[k].comparison_operator == "LessThanThreshold"])
    error_message = "*_missing: < 0, breaching, 60s x 2"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_throttling"].threshold == 0.9 && aws_cloudwatch_metric_alarm.this["memory_pressure"].threshold == 0.85
    error_message = "Container thresholds default to 0.9 and 0.85"
  }

  assert {
    condition     = alltrue([for k in ["cpu_throttling", "memory_pressure"] : aws_cloudwatch_metric_alarm.this[k].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.this[k].datapoints_to_alarm == 2 && aws_cloudwatch_metric_alarm.this[k].treat_missing_data == "notBreaching"])
    error_message = "Container ratio alarms: 2 of 3, notBreaching"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["tasks_below_desired"].threshold == 0 && aws_cloudwatch_metric_alarm.this["tasks_below_desired"].evaluation_periods == 5 && aws_cloudwatch_metric_alarm.this["tasks_below_desired"].datapoints_to_alarm == 3 && aws_cloudwatch_metric_alarm.this["tasks_below_desired"].comparison_operator == "GreaterThanThreshold"
    error_message = "tasks_below_desired: deficit > 0, 3 of 5"
  }
}

run "at_max_capacity_only_with_max" {
  command = plan

  variables {
    max_capacity = 6
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["at_max_capacity"].threshold == 6 && aws_cloudwatch_metric_alarm.this["at_max_capacity"].evaluation_periods == 5 && aws_cloudwatch_metric_alarm.this["at_max_capacity"].period == 60 && aws_cloudwatch_metric_alarm.this["at_max_capacity"].statistic == "Maximum"
    error_message = "at_max_capacity: Maximum RunningTaskCount >= 6, 60s x 5"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 8
    error_message = "max_capacity adds exactly one alarm"
  }
}

run "no_at_max_capacity_without_max" {
  command = plan

  variables {
    max_capacity = null
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "at_max_capacity")
    error_message = "null max_capacity must not create at_max_capacity"
  }
}

run "alb_alarms_with_lb" {
  command = plan

  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 12
    error_message = "A load balancer adds exactly 5 alarms"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].threshold == 0.01 && aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].evaluation_periods == 1 && aws_cloudwatch_metric_alarm.this["target_4xx_ratio"].threshold == 0.05 && aws_cloudwatch_metric_alarm.this["target_4xx_ratio"].datapoints_to_alarm == 2
    error_message = "Target 5xx 0.01 (1 period) and 4xx 0.05 (2 of 3)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["latency_p95"].threshold == 0.8 && aws_cloudwatch_metric_alarm.this["latency_p95"].extended_statistic == "p95" && aws_cloudwatch_metric_alarm.this["latency_p95"].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.this["latency_p95"].metric_name == "TargetResponseTime"
    error_message = "latency_p95: 800 ms becomes 0.8 s, p95, 3 periods"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].threshold == 1 && aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].statistic == "Minimum" && aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].datapoints_to_alarm == 2
    error_message = "unhealthy_hosts: Minimum HealthyHostCount < 1, 2 of 3"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["target_connection_errors"].threshold == 0 && aws_cloudwatch_metric_alarm.this["target_connection_errors"].statistic == "Sum" && aws_cloudwatch_metric_alarm.this["target_connection_errors"].metric_name == "TargetConnectionErrorCount"
    error_message = "target_connection_errors: Sum > 0"
  }

  assert {
    condition     = !anytrue([for k, a in aws_cloudwatch_metric_alarm.this : a.metric_name == "HTTPCode_ELB_5XX_Count"])
    error_message = "ELB 5xx belongs to the alb module"
  }
}

run "no_lb_no_alb_alarms" {
  command = plan

  assert {
    condition     = length(setintersection(toset(keys(aws_cloudwatch_metric_alarm.this)), toset(["target_5xx_ratio", "target_4xx_ratio", "latency_p95", "unhealthy_hosts", "target_connection_errors"]))) == 0
    error_message = "Without load_balancer there must be no ALB alarms"
  }
}

run "override_one_threshold_keeps_others" {
  command = plan

  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
    alarm_config  = { ecs = { cpu_threshold = 90 } }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].threshold == 90 && aws_cloudwatch_metric_alarm.this["memory_high"].threshold == 80
    error_message = "Only cpu_threshold changes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_throttling"].threshold == 0.9 && aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].threshold == 0.01 && aws_cloudwatch_metric_alarm.this["latency_p95"].threshold == 0.8
    error_message = "container and alb defaults must stay"
  }
}

run "override_alb_and_container_thresholds" {
  command = plan

  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
    alarm_config = {
      container = { cpu_throttling_threshold = 0.5, memory_pressure_threshold = 0.6 }
      alb       = { latency_p95_threshold_ms = 2000, healthy_host_min = 2, target_4xx_ratio_threshold = 0.2, target_5xx_ratio_threshold = 0.1 }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_throttling"].threshold == 0.5 && aws_cloudwatch_metric_alarm.this["memory_pressure"].threshold == 0.6 && aws_cloudwatch_metric_alarm.this["latency_p95"].threshold == 2 && aws_cloudwatch_metric_alarm.this["unhealthy_hosts"].threshold == 2 && aws_cloudwatch_metric_alarm.this["target_4xx_ratio"].threshold == 0.2 && aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].threshold == 0.1
    error_message = "Every container and alb threshold must follow alarm_config"
  }
}

run "dimensions_point_to_service" {
  command = plan

  variables {
    max_capacity  = 6
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }

  assert {
    condition     = alltrue([for k in ["cpu_high", "memory_high", "cpu_missing", "memory_missing", "at_max_capacity"] : aws_cloudwatch_metric_alarm.this[k].dimensions == tomap({ ClusterName = "alpha-dev", ServiceName = "alpha-api" })])
    error_message = "ECS alarms must carry ClusterName and ServiceName"
  }

  assert {
    condition     = alltrue([for k in ["latency_p95", "unhealthy_hosts", "target_connection_errors"] : aws_cloudwatch_metric_alarm.this[k].dimensions == tomap({ LoadBalancer = "app/alpha/abc", TargetGroup = "targetgroup/alpha-api/def" })])
    error_message = "ALB alarms must carry LoadBalancer and TargetGroup"
  }

  assert {
    condition     = alltrue([for q in aws_cloudwatch_metric_alarm.this["target_5xx_ratio"].metric_query : q.metric == null || length(q.metric) == 0 || q.metric[0].dimensions == tomap({ LoadBalancer = "app/alpha/abc", TargetGroup = "targetgroup/alpha-api/def" })])
    error_message = "Ratio alarm queries must carry LoadBalancer and TargetGroup"
  }

  assert {
    condition     = alltrue([for q in aws_cloudwatch_metric_alarm.this["cpu_throttling"].metric_query : length(q.metric) == 0 || q.metric[0].dimensions == tomap({ ClusterName = "alpha-dev", ServiceName = "alpha-api" })])
    error_message = "Container Insights queries must carry ClusterName and ServiceName"
  }
}

run "tags_are_applied" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.tags == tomap({ Project = "alpha" })])
    error_message = "Input tags must be set on every alarm"
  }
}

run "outputs_expose_alarms" {
  command = plan

  assert {
    condition     = output.alarm_names == { for k in ["cpu_high", "memory_high", "cpu_missing", "memory_missing", "tasks_below_desired", "cpu_throttling", "memory_pressure"] : k => "alpha-api-${k}" }
    error_message = "alarm_names must map key to <name>-<key>"
  }
}
