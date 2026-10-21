mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      name   = "ap-northeast-1"
      region = "ap-northeast-1"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "111111111111"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

variables {
  name                     = "dev-web"
  load_balancer_type       = "application"
  load_balancer_arn_suffix = "app/dev-web/0123456789abcdef"
  lambda_function_arn      = "arn:aws:lambda:ap-northeast-1:111111111111:function:dev-web-breaker"
  sns_topic_arns           = ["arn:aws:sns:ap-northeast-1:111111111111:dev-alarms"]
  breakers = {
    api = {
      listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
      stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
      canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
    }
  }
}

# ---------------------------------------------------------------------------
# ALB alarms
# ---------------------------------------------------------------------------

run "alb_creates_error_rate_and_healthy_hosts_alarms" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 1 && length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1
    error_message = "ALB must get one error-rate and one healthy-hosts alarm per breaker"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.custom) == 0
    error_message = "No custom alarm without custom_metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["api"].alarm_name == "dev-web-api-error-rate"
    error_message = "Error-rate alarm name must be <name>-<key>-error-rate"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].alarm_name == "dev-web-api-healthy-hosts"
    error_message = "Healthy-hosts alarm name must be <name>-<key>-healthy-hosts"
  }

  assert {
    condition     = toset(keys(output.alarm_names)) == toset(["api-error-rate", "api-healthy-hosts"]) && output.alarm_names["api-error-rate"] == "dev-web-api-error-rate" && output.alarm_names["api-healthy-hosts"] == "dev-web-api-healthy-hosts"
    error_message = "alarm_names must list every alarm keyed by <key>-<signal>"
  }
}

run "alb_error_rate_uses_metric_math_with_min_requests_guard" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.error_rate["api"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.error_rate["api"].threshold == 5 &&
      aws_cloudwatch_metric_alarm.error_rate["api"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.error_rate["api"].datapoints_to_alarm == 2
    )
    error_message = "Error-rate alarm must default to > 5 percent, 2 of 3 datapoints"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["api"].treat_missing_data == "notBreaching"
    error_message = "Error-rate alarm must treat missing data as notBreaching"
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q.expression if q.return_data]) == "IF(requests >= 50, 100 * FILL(errors, 0) / requests, 0)"
    error_message = "The returned query must be the 5xx percentage guarded by min_requests"
  }

  assert {
    condition = (
      length([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q if !q.return_data]) == 2 &&
      one([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q.metric[0].metric_name if q.id == "errors"]) == "HTTPCode_Target_5XX_Count" &&
      one([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q.metric[0].metric_name if q.id == "requests"]) == "RequestCount"
    )
    error_message = "errors and requests must be HTTPCode_Target_5XX_Count and RequestCount"
  }

  assert {
    condition = alltrue([
      for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query :
      q.metric[0].namespace == "AWS/ApplicationELB" &&
      q.metric[0].stat == "Sum" &&
      q.metric[0].period == 60 &&
      q.metric[0].dimensions == tomap({ LoadBalancer = "app/dev-web/0123456789abcdef", TargetGroup = "targetgroup/dev-new/2222222222222222" })
      if !q.return_data
    ])
    error_message = "Both raw metrics must be Sum per period, scoped to the canary target group and the load balancer"
  }
}

run "alb_custom_error_rate_and_min_requests_are_applied" {
  command = plan

  variables {
    breakers = {
      api = {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        error_rate_percent             = 10
        min_requests                   = 200
        period                         = 120
        evaluation_periods             = 5
        datapoints_to_alarm            = 3
      }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.error_rate["api"].threshold == 10 &&
      aws_cloudwatch_metric_alarm.error_rate["api"].evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.error_rate["api"].datapoints_to_alarm == 3 &&
      one([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q.expression if q.return_data]) == "IF(requests >= 200, 100 * FILL(errors, 0) / requests, 0)"
    )
    error_message = "error_rate_percent, min_requests, evaluation_periods and datapoints_to_alarm must be applied"
  }

  assert {
    condition     = alltrue([for q in aws_cloudwatch_metric_alarm.error_rate["api"].metric_query : q.metric[0].period == 120 if !q.return_data])
    error_message = "period must be applied to the raw metrics"
  }
}

run "alb_healthy_hosts_alarm" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].namespace == "AWS/ApplicationELB" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].metric_name == "HealthyHostCount" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].statistic == "Minimum" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].comparison_operator == "LessThanThreshold" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].threshold == 1 &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].period == 60 &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].datapoints_to_alarm == 2
    )
    error_message = "Healthy-hosts alarm must be Minimum HealthyHostCount < 1, 2 of 3 datapoints, 60 seconds"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].dimensions == tomap({ LoadBalancer = "app/dev-web/0123456789abcdef", TargetGroup = "targetgroup/dev-new/2222222222222222" })
    error_message = "Healthy-hosts alarm must be scoped to the canary target group and the load balancer"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].treat_missing_data == "breaching"
    error_message = "Healthy-hosts alarm must treat missing data as breaching"
  }
}

run "alb_with_custom_metric_has_three_alarms" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace   = "Alpha/Checkout"
          metric_name = "FailedOrders"
          dimensions  = { Environment = "dev" }
          statistic   = "Sum"
          threshold   = 20
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) + length(aws_cloudwatch_metric_alarm.healthy_hosts) + length(aws_cloudwatch_metric_alarm.custom) == 3
    error_message = "ALB with custom_metric must have error-rate, healthy-hosts and custom alarms"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.custom["api"].alarm_name == "dev-web-api-custom" &&
      aws_cloudwatch_metric_alarm.custom["api"].namespace == "Alpha/Checkout" &&
      aws_cloudwatch_metric_alarm.custom["api"].metric_name == "FailedOrders" &&
      aws_cloudwatch_metric_alarm.custom["api"].statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.custom["api"].threshold == 20 &&
      aws_cloudwatch_metric_alarm.custom["api"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.custom["api"].dimensions == tomap({ Environment = "dev" }) &&
      aws_cloudwatch_metric_alarm.custom["api"].treat_missing_data == "notBreaching" &&
      aws_cloudwatch_metric_alarm.custom["api"].period == 60 &&
      aws_cloudwatch_metric_alarm.custom["api"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.custom["api"].datapoints_to_alarm == 2
    )
    error_message = "Custom alarm must use the custom metric, default operator and the breaker's period settings"
  }
}

# ---------------------------------------------------------------------------
# NLB alarms
# ---------------------------------------------------------------------------

run "nlb_has_only_healthy_hosts_alarm" {
  command = plan

  variables {
    load_balancer_type       = "network"
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
    breakers = {
      tcp = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate) == 0 && length(aws_cloudwatch_metric_alarm.custom) == 0 && length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1
    error_message = "NLB must only get the healthy-hosts alarm"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.healthy_hosts["tcp"].namespace == "AWS/NetworkELB" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["tcp"].alarm_name == "dev-web-tcp-healthy-hosts" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["tcp"].treat_missing_data == "breaching" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["tcp"].dimensions == tomap({ LoadBalancer = "net/dev-web/0123456789abcdef", TargetGroup = "targetgroup/dev-new/2222222222222222" })
    )
    error_message = "NLB healthy-hosts alarm must use AWS/NetworkELB with the net/ load balancer dimension"
  }
}

run "nlb_with_custom_metric_has_two_alarms" {
  command = plan

  variables {
    load_balancer_type       = "network"
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
    breakers = {
      tcp = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace           = "Alpha/Gateway"
          metric_name         = "ConnectionErrors"
          statistic           = "Sum"
          threshold           = 10
          comparison_operator = "GreaterThanOrEqualToThreshold"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1 && length(aws_cloudwatch_metric_alarm.custom) == 1 && length(aws_cloudwatch_metric_alarm.error_rate) == 0
    error_message = "NLB with custom_metric must have healthy-hosts and custom alarms, never error-rate"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.custom["tcp"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "comparison_operator of the custom metric must be applied"
  }
}

run "nlb_rejects_error_rate_percent" {
  command = plan

  variables {
    load_balancer_type       = "network"
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
    breakers = {
      tcp = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        error_rate_percent             = 5
      }
    }
  }

  expect_failures = [var.breakers]
}

run "nlb_rejects_min_requests" {
  command = plan

  variables {
    load_balancer_type       = "network"
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
    breakers = {
      tcp = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/net/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        min_requests                   = 50
      }
    }
  }

  expect_failures = [var.breakers]
}

run "nlb_rejects_rule_arn" {
  command = plan

  variables {
    load_balancer_type       = "network"
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
    breakers = {
      tcp = {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/net/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

# ---------------------------------------------------------------------------
# listener_arn / rule_arn
# ---------------------------------------------------------------------------

run "rule_arn_alone_is_accepted_on_alb" {
  command = plan

  variables {
    breakers = {
      api = {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1
    error_message = "A rule_arn on its own must be accepted for an ALB"
  }
}

run "listener_and_rule_together_are_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "neither_listener_nor_rule_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "listener_of_another_load_balancer_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/other-lb/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "rule_of_another_load_balancer_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/other-lb/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "listener_arn_that_is_not_a_listener_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/dev-web/0123456789abcdef"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

# ---------------------------------------------------------------------------
# Target groups and numeric settings
# ---------------------------------------------------------------------------

run "stable_equal_to_canary_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-new/2222222222222222"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "stable_target_group_arn_must_be_an_arn" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "canary_suffix_must_be_a_suffix_not_an_arn" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "error_rate_percent_above_100_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        error_rate_percent             = 101
      }
    }
  }

  expect_failures = [var.breakers]
}

run "error_rate_percent_of_100_is_accepted" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        error_rate_percent             = 100
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate["api"].threshold == 100
    error_message = "error_rate_percent = 100 is the upper bound and must be accepted"
  }
}

run "error_rate_percent_of_zero_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        error_rate_percent             = 0
      }
    }
  }

  expect_failures = [var.breakers]
}

run "min_requests_of_zero_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        min_requests                   = 0
      }
    }
  }

  expect_failures = [var.breakers]
}

run "min_healthy_hosts_of_zero_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        min_healthy_hosts              = 0
      }
    }
  }

  expect_failures = [var.breakers]
}

run "min_healthy_hosts_of_two_is_applied" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        min_healthy_hosts              = 2
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].threshold == 2
    error_message = "min_healthy_hosts must be the alarm threshold"
  }
}

run "period_not_a_multiple_of_60_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        period                         = 90
      }
    }
  }

  expect_failures = [var.breakers]
}

run "period_below_60_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        period                         = 30
      }
    }
  }

  expect_failures = [var.breakers]
}

run "datapoints_above_evaluation_periods_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        evaluation_periods             = 2
        datapoints_to_alarm            = 3
      }
    }
  }

  expect_failures = [var.breakers]
}

run "datapoints_equal_to_evaluation_periods_is_accepted" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        evaluation_periods             = 2
        datapoints_to_alarm            = 2
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].evaluation_periods == 2 && aws_cloudwatch_metric_alarm.healthy_hosts["api"].datapoints_to_alarm == 2
    error_message = "datapoints_to_alarm equal to evaluation_periods must be accepted"
  }
}

run "evaluation_window_above_one_day_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        period                         = 3600
        evaluation_periods             = 25
        datapoints_to_alarm            = 2
      }
    }
  }

  expect_failures = [var.breakers]
}

run "breaker_key_must_be_lowercase_kebab" {
  command = plan

  variables {
    breakers = {
      Api_Rule = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
    }
  }

  expect_failures = [var.breakers]
}

run "empty_breakers_are_rejected" {
  command = plan

  variables {
    breakers = {}
  }

  expect_failures = [var.breakers]
}

run "custom_metric_with_unsupported_statistic_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace   = "Alpha/Checkout"
          metric_name = "FailedOrders"
          statistic   = "p99"
          threshold   = 20
        }
      }
    }
  }

  expect_failures = [var.breakers]
}

run "custom_metric_with_unsupported_operator_is_rejected" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace           = "Alpha/Checkout"
          metric_name         = "FailedOrders"
          threshold           = 20
          comparison_operator = "Equals"
        }
      }
    }
  }

  expect_failures = [var.breakers]
}

# ---------------------------------------------------------------------------
# Other inputs
# ---------------------------------------------------------------------------

run "load_balancer_type_must_be_application_or_network" {
  command = plan

  variables {
    load_balancer_type = "gateway"
  }

  expect_failures = [var.load_balancer_type]
}

run "load_balancer_suffix_must_match_the_type" {
  command = plan

  variables {
    load_balancer_arn_suffix = "net/dev-web/0123456789abcdef"
  }

  expect_failures = [var.load_balancer_arn_suffix]
}

run "name_must_be_lowercase_kebab" {
  command = plan

  variables {
    name = "Dev_Web"
  }

  expect_failures = [var.name]
}

run "lambda_function_arn_with_qualifier_is_rejected" {
  command = plan

  variables {
    lambda_function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:dev-web-breaker:live"
  }

  expect_failures = [var.lambda_function_arn]
}

run "lambda_function_arn_must_be_a_function_arn" {
  command = plan

  variables {
    lambda_function_arn = "dev-web-breaker"
  }

  expect_failures = [var.lambda_function_arn]
}

run "empty_sns_topic_arns_are_rejected" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "sns_topic_arns_must_be_sns_arns" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:dev-alarms"]
  }

  expect_failures = [var.sns_topic_arns]
}

# ---------------------------------------------------------------------------
# Alarm actions, tags
# ---------------------------------------------------------------------------

run "alarm_actions_have_lambda_and_sns_and_ok_actions_only_sns" {
  command = plan

  variables {
    sns_topic_arns = [
      "arn:aws:sns:ap-northeast-1:111111111111:dev-alarms",
      "arn:aws:sns:ap-northeast-1:111111111111:dev-pager",
    ]
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace   = "Alpha/Checkout"
          metric_name = "FailedOrders"
          threshold   = 20
        }
      }
    }
  }

  assert {
    condition = alltrue([
      for a in [
        aws_cloudwatch_metric_alarm.error_rate["api"],
        aws_cloudwatch_metric_alarm.healthy_hosts["api"],
        aws_cloudwatch_metric_alarm.custom["api"],
        ] : (
        length(a.alarm_actions) == 3 &&
        contains(a.alarm_actions, "arn:aws:lambda:ap-northeast-1:111111111111:function:dev-web-breaker") &&
        contains(a.alarm_actions, "arn:aws:sns:ap-northeast-1:111111111111:dev-alarms") &&
        contains(a.alarm_actions, "arn:aws:sns:ap-northeast-1:111111111111:dev-pager")
      )
    ])
    error_message = "alarm_actions of every alarm must be the Lambda function plus all SNS topics"
  }

  assert {
    condition = alltrue([
      for a in [
        aws_cloudwatch_metric_alarm.error_rate["api"],
        aws_cloudwatch_metric_alarm.healthy_hosts["api"],
        aws_cloudwatch_metric_alarm.custom["api"],
        ] : (
        toset(a.ok_actions) == toset(["arn:aws:sns:ap-northeast-1:111111111111:dev-alarms", "arn:aws:sns:ap-northeast-1:111111111111:dev-pager"])
      )
    ])
    error_message = "ok_actions must only notify SNS; the Lambda must never be invoked on recovery"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].tags["Project"] == "alpha" &&
      aws_cloudwatch_metric_alarm.healthy_hosts["api"].tags["Name"] == "dev-web-api-healthy-hosts" &&
      aws_cloudwatch_metric_alarm.error_rate["api"].tags["Name"] == "dev-web-api-error-rate"
    )
    error_message = "tags must be merged with a Name tag equal to the alarm name"
  }
}

# ---------------------------------------------------------------------------
# lambda_permissions
# ---------------------------------------------------------------------------

run "lambda_permissions_point_at_each_alarm_by_name" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace   = "Alpha/Checkout"
          metric_name = "FailedOrders"
          threshold   = 20
        }
      }
    }
  }

  assert {
    condition     = toset(keys(output.lambda_permissions)) == toset(["dev-web-api-error-rate", "dev-web-api-healthy-hosts", "dev-web-api-custom"])
    error_message = "One permission per alarm, keyed by the alarm name"
  }

  assert {
    condition = alltrue([
      for name, p in output.lambda_permissions :
      p.principal == "lambda.alarms.cloudwatch.amazonaws.com" &&
      p.source_arn == "arn:aws:cloudwatch:ap-northeast-1:111111111111:alarm:${name}" &&
      p.source_account == "111111111111"
    ])
    error_message = "Each permission must allow the CloudWatch alarms principal from exactly that alarm ARN and the account"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts["api"].alarm_name == "dev-web-api-healthy-hosts" && output.lambda_permissions["dev-web-api-healthy-hosts"].source_arn == "arn:aws:cloudwatch:ap-northeast-1:111111111111:alarm:dev-web-api-healthy-hosts"
    error_message = "source_arn must match the name of the alarm the module creates"
  }
}

# ---------------------------------------------------------------------------
# lambda_config_json
# ---------------------------------------------------------------------------

run "lambda_config_json_maps_alarm_names_to_targets" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
      }
      admin = {
        rule_arn                       = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old-admin/3333333333333333"
        canary_target_group_arn_suffix = "targetgroup/dev-new-admin/4444444444444444"
      }
    }
  }

  assert {
    condition     = jsondecode(output.lambda_config_json).schema_version == 1
    error_message = "lambda_config_json must carry schema_version 1"
  }

  assert {
    condition     = toset(keys(jsondecode(output.lambda_config_json).alarms)) == toset(["dev-web-api-error-rate", "dev-web-api-healthy-hosts", "dev-web-admin-error-rate", "dev-web-admin-healthy-hosts"])
    error_message = "Every alarm name must have an entry"
  }

  assert {
    condition = (
      jsondecode(output.lambda_config_json).alarms["dev-web-api-error-rate"] == {
        listener_arn            = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
      } &&
      jsondecode(output.lambda_config_json).alarms["dev-web-api-healthy-hosts"] == jsondecode(output.lambda_config_json).alarms["dev-web-api-error-rate"]
    )
    error_message = "A listener breaker must map every alarm to listener_arn and stable_target_group_arn only"
  }

  assert {
    condition = (
      jsondecode(output.lambda_config_json).alarms["dev-web-admin-healthy-hosts"] == {
        rule_arn                = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
        stable_target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old-admin/3333333333333333"
      }
    )
    error_message = "A rule breaker must map to rule_arn and stable_target_group_arn only"
  }
}

run "lambda_config_json_includes_custom_alarm" {
  command = plan

  variables {
    breakers = {
      api = {
        listener_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
        stable_target_group_arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/dev-old/1111111111111111"
        canary_target_group_arn_suffix = "targetgroup/dev-new/2222222222222222"
        custom_metric = {
          namespace   = "Alpha/Checkout"
          metric_name = "FailedOrders"
          threshold   = 20
        }
      }
    }
  }

  assert {
    condition     = contains(keys(jsondecode(output.lambda_config_json).alarms), "dev-web-api-custom")
    error_message = "The custom alarm must also be in lambda_config_json"
  }
}
