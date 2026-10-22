mock_provider "aws" {}

variables {
  name           = "alpha-api"
  cluster_name   = "alpha-dev"
  namespace      = "alpha"
  workload_name  = "alpha-api"
  container_name = "api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "valid_inputs_pass" {
  command = plan
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 5
    error_message = "Valid inputs must plan the 5 workload alarms"
  }
}

run "name_uppercase" {
  command = plan
  variables {
    name = "Alpha"
  }
  expect_failures = [var.name]
}

run "cluster_name_empty" {
  command = plan
  variables {
    cluster_name = ""
  }
  expect_failures = [var.cluster_name]
}

run "namespace_invalid" {
  command = plan
  variables {
    namespace = "Alpha_NS"
  }
  expect_failures = [var.namespace]
}

run "workload_name_empty" {
  command = plan
  variables {
    workload_name = ""
  }
  expect_failures = [var.workload_name]
}

run "container_name_empty" {
  command = plan
  variables {
    container_name = ""
  }
  expect_failures = [var.container_name]
}

run "sns_topic_empty" {
  command = plan
  variables {
    sns_topic_arns = []
  }
  expect_failures = [var.sns_topic_arns]
}

run "sns_arn_is_sqs" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:q"]
  }
  expect_failures = [var.sns_topic_arns]
}

run "alb_suffix_without_app_prefix" {
  command = plan
  variables {
    load_balancer = { alb_arn_suffix = "alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }
  expect_failures = [var.load_balancer]
}

run "tg_suffix_is_full_arn" {
  command = plan
  variables {
    load_balancer = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api/def" }
  }
  expect_failures = [var.load_balancer]
}

run "restart_threshold_negative" {
  command = plan
  variables {
    restart_threshold = -1
  }
  expect_failures = [var.restart_threshold]
}

run "latency_threshold_not_positive" {
  command = plan
  variables {
    alarm_config = { alb = { latency_p95_threshold_ms = 0 } }
  }
  expect_failures = [var.alarm_config]
}
