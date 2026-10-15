mock_provider "aws" {}

variables {
  name_prefix    = "alpha-dev-api"
  log_group_name = "/ecs/alpha-dev-api"
  namespace      = "Alpha/dev"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  alarms = {
    write_failed = {
      pattern     = "{ $.event = \"persistence_write_failed\" }"
      metric_name = "PersistenceWriteFailed"
      description = "Audit writes failed. Check the database first."
    }
    queue_full = {
      pattern     = "{ $.event = \"persistence_queue_full\" }"
      metric_name = "PersistenceQueueFull"
      description = "Audit queue is full. Check the flusher."
    }
  }
}

run "one_filter_and_alarm_per_entry" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 2 && length(aws_cloudwatch_metric_alarm.this) == 2
    error_message = "Each alarms entry must create one metric filter and one alarm"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].name == "alpha-dev-api-write-failed"
    error_message = "Filter name must be <name_prefix>-<key with _ replaced by ->"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["queue_full"].alarm_name == "alpha-dev-api-queue-full"
    error_message = "Alarm name must be <name_prefix>-<key with _ replaced by ->"
  }
}

run "filter_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].log_group_name == "/ecs/alpha-dev-api"
    error_message = "Filter must read from log_group_name"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].pattern == "{ $.event = \"persistence_write_failed\" }"
    error_message = "Filter pattern must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].metric_transformation[0].value == "1"
    error_message = "Default metric value must be 1"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].metric_transformation[0].default_value == "0"
    error_message = "Default default_value must be 0"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].metric_transformation[0].namespace == "Alpha/dev"
    error_message = "Metric namespace must follow the namespace input"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["write_failed"].metric_transformation[0].name == "PersistenceWriteFailed"
    error_message = "Metric name must follow metric_name"
  }
}

run "alarm_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].statistic == "Sum"
    error_message = "Default statistic must be Sum"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].period == 60
    error_message = "Default period must be 60"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].evaluation_periods == 1
    error_message = "Default evaluation_periods must be 1"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].threshold == 1
    error_message = "Default threshold must be 1"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Default comparison operator must be GreaterThanOrEqualToThreshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].treat_missing_data == "notBreaching"
    error_message = "Default treat_missing_data must be notBreaching"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].datapoints_to_alarm == null
    error_message = "datapoints_to_alarm must stay unset by default"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].namespace == "Alpha/dev" && aws_cloudwatch_metric_alarm.this["write_failed"].metric_name == "PersistenceWriteFailed"
    error_message = "Alarm must watch the metric the filter produces"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].alarm_description == "Audit writes failed. Check the database first."
    error_message = "alarm_description must follow description"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["write_failed"].tags == tomap({ Name = "alpha-dev-api-write-failed" })
    error_message = "Without tags input the only alarm tag is Name"
  }
}

run "alarm_override" {
  command = plan

  variables {
    alarms = {
      rate_limit_fail_open = {
        pattern             = "{ $.event = \"rate_limit_fail_open\" }"
        metric_name         = "RateLimitFailOpen"
        description         = "Rate limiter failed open."
        period              = 300
        threshold           = 60
        evaluation_periods  = 3
        datapoints_to_alarm = 2
        statistic           = "Average"
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        metric_value        = "$.count"
        default_value       = 5
      }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].period == 300 &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].threshold == 60 &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].datapoints_to_alarm == 2 &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].statistic == "Average" &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["rate_limit_fail_open"].treat_missing_data == "missing"
    )
    error_message = "Alarm settings must follow the input"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["rate_limit_fail_open"].metric_transformation[0].value == "$.count" && aws_cloudwatch_log_metric_filter.this["rate_limit_fail_open"].metric_transformation[0].default_value == "5"
    error_message = "Metric value and default value must follow the input"
  }
}

run "every_alarm_notifies_both_ways" {
  command = plan

  variables {
    sns_topic_arns = [
      "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms",
      "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-pager",
    ]
  }

  assert {
    condition = alltrue([
      for a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(var.sns_topic_arns)
    ])
    error_message = "Every alarm must send alarm_actions to all sns_topic_arns"
  }

  assert {
    condition = alltrue([
      for a in aws_cloudwatch_metric_alarm.this : a.ok_actions == toset(var.sns_topic_arns)
    ])
    error_message = "Every alarm must send ok_actions to all sns_topic_arns"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["queue_full"].tags == tomap({ Project = "alpha", Name = "alpha-dev-api-queue-full" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "empty_alarms_creates_nothing" {
  command = plan

  variables {
    alarms = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 0 && length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "alarms = {} must create nothing"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = toset(keys(output.alarm_arns)) == toset(["write_failed", "queue_full"])
    error_message = "alarm_arns keys must equal the alarms keys"
  }

  assert {
    condition     = toset(keys(output.alarm_names)) == toset(["write_failed", "queue_full"]) && output.alarm_names["queue_full"] == "alpha-dev-api-queue-full"
    error_message = "alarm_names must be keyed by the alarms keys and carry the alarm name"
  }

  assert {
    condition     = toset(keys(output.metric_filter_names)) == toset(["write_failed", "queue_full"]) && output.metric_filter_names["write_failed"] == "alpha-dev-api-write-failed"
    error_message = "metric_filter_names must be keyed by the alarms keys and carry the filter name"
  }
}

run "sns_topic_required" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "sns_topic_malformed_rejected" {
  command = plan

  variables {
    sns_topic_arns = ["not-an-arn"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "key_not_snake_case_rejected" {
  command = plan

  variables {
    alarms = {
      PersistenceFailed = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
      }
    }
  }

  expect_failures = [var.alarms]
}

run "blank_pattern_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = " "
        metric_name = "M"
        description = "d"
      }
    }
  }

  expect_failures = [var.alarms]
}

run "empty_description_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = ""
      }
    }
  }

  expect_failures = [var.alarms]
}

run "snake_case_key_with_digits_passes" {
  command = plan

  variables {
    alarms = {
      a_1 = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a_1"].alarm_name == "alpha-dev-api-a-1"
    error_message = "A snake_case key with digits must be accepted"
  }
}

run "statistic_p99_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        statistic   = "p99"
      }
    }
  }

  expect_failures = [var.alarms]
}

run "statistic_average_passes" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        statistic   = "Average"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].statistic == "Average"
    error_message = "Average must be accepted"
  }
}

run "comparison_operator_unknown_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern             = "ERROR"
        metric_name         = "M"
        description         = "d"
        comparison_operator = "Equals"
      }
    }
  }

  expect_failures = [var.alarms]
}

run "treat_missing_data_unknown_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern            = "ERROR"
        metric_name        = "M"
        description        = "d"
        treat_missing_data = "ok"
      }
    }
  }

  expect_failures = [var.alarms]
}

run "period_45_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        period      = 45
      }
    }
  }

  expect_failures = [var.alarms]
}

run "period_10_passes" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        period      = 10
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 10
    error_message = "Period 10 must be accepted"
  }
}

run "period_30_passes" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        period      = 30
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 30
    error_message = "Period 30 must be accepted"
  }
}

run "period_120_passes" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern     = "ERROR"
        metric_name = "M"
        description = "d"
        period      = 120
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 120
    error_message = "Period 120 must be accepted"
  }
}

run "datapoints_above_periods_rejected" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern             = "ERROR"
        metric_name         = "M"
        description         = "d"
        evaluation_periods  = 2
        datapoints_to_alarm = 3
      }
    }
  }

  expect_failures = [var.alarms]
}

run "datapoints_equal_periods_passes" {
  command = plan

  variables {
    alarms = {
      a = {
        pattern             = "ERROR"
        metric_name         = "M"
        description         = "d"
        evaluation_periods  = 2
        datapoints_to_alarm = 2
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].datapoints_to_alarm == 2
    error_message = "datapoints_to_alarm equal to evaluation_periods must be accepted"
  }
}

run "namespace_aws_prefix_rejected" {
  command = plan

  variables {
    namespace = "AWS/ECS"
  }

  expect_failures = [var.namespace]
}

run "namespace_custom_passes" {
  command = plan

  variables {
    namespace = "Alpha/dev"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["queue_full"].metric_transformation[0].namespace == "Alpha/dev"
    error_message = "A custom namespace must be accepted"
  }
}

run "name_prefix_uppercase_rejected" {
  command = plan

  variables {
    name_prefix = "Alpha-dev"
  }

  expect_failures = [var.name_prefix]
}
