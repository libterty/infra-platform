mock_provider "aws" {}

variables {
  name_prefix    = "alpha-dev-api"
  sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  alarms = {
    cpu_high = {
      description         = "CPU is high. Check the instance load first."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 80
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      metric = {
        namespace   = "AWS/EC2"
        metric_name = "CPUUtilization"
        dimensions  = { InstanceId = "i-0123456789abcdef0" }
      }
    }
    error_rate = {
      description         = "Error rate is high. Check the application logs first."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 5
      queries = [
        {
          id = "errors"
          metric = {
            namespace   = "AWS/ApplicationELB"
            metric_name = "HTTPCode_Target_5XX_Count"
            statistic   = "Sum"
            dimensions  = { LoadBalancer = "app/alpha-dev/0123456789abcdef" }
          }
        },
        {
          id = "requests"
          metric = {
            namespace   = "AWS/ApplicationELB"
            metric_name = "RequestCount"
            statistic   = "Sum"
            dimensions  = { LoadBalancer = "app/alpha-dev/0123456789abcdef" }
          }
        },
        {
          id          = "rate"
          expression  = "100 * errors / requests"
          label       = "Error rate"
          return_data = true
        },
      ]
    }
  }
}

run "one_alarm_per_entry_with_prefix_naming" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 2
    error_message = "Each alarms entry must create one alarm"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].alarm_name == "alpha-dev-api-cpu-high"
    error_message = "Alarm name must be <name_prefix>-<key with _ replaced by ->"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["error_rate"].alarm_name == "alpha-dev-api-error-rate"
    error_message = "Alarm name must be <name_prefix>-<key with _ replaced by ->"
  }
}

run "single_metric_alarm" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["cpu_high"].namespace == "AWS/EC2" &&
      aws_cloudwatch_metric_alarm.this["cpu_high"].metric_name == "CPUUtilization" &&
      aws_cloudwatch_metric_alarm.this["cpu_high"].dimensions == tomap({ InstanceId = "i-0123456789abcdef0" })
    )
    error_message = "Single metric alarm must carry namespace, metric_name and dimensions"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].statistic == "Average" && aws_cloudwatch_metric_alarm.this["cpu_high"].period == 300
    error_message = "Default statistic must be Average and default period 300"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["cpu_high"].metric_query) == 0
    error_message = "A single metric alarm must not have metric_query blocks"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["cpu_high"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["cpu_high"].threshold == 80 &&
      aws_cloudwatch_metric_alarm.this["cpu_high"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.this["cpu_high"].datapoints_to_alarm == 2
    )
    error_message = "Threshold settings must follow the input"
  }
}

run "metric_math_alarm" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["error_rate"].metric_query) == 3
    error_message = "A queries alarm must have one metric_query per query"
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["error_rate"].metric_name == null &&
      aws_cloudwatch_metric_alarm.this["error_rate"].namespace == null &&
      aws_cloudwatch_metric_alarm.this["error_rate"].statistic == null
    )
    error_message = "A queries alarm must not set the single metric attributes"
  }

  assert {
    condition     = [for q in aws_cloudwatch_metric_alarm.this["error_rate"].metric_query : q.id if q.return_data] == ["rate"]
    error_message = "Only the rate query must return data"
  }

  assert {
    condition     = [for q in aws_cloudwatch_metric_alarm.this["error_rate"].metric_query : q.expression if q.id == "rate"] == ["100 * errors / requests"]
    error_message = "The expression must be passed through"
  }

  assert {
    condition     = [for q in aws_cloudwatch_metric_alarm.this["error_rate"].metric_query : q.metric[0].stat if q.id == "errors"] == ["Sum"]
    error_message = "Query metric statistic must be passed through as stat"
  }

  assert {
    condition     = [for q in aws_cloudwatch_metric_alarm.this["error_rate"].metric_query : q.metric[0].period if q.id == "requests"] == [300]
    error_message = "Query metric default period must be 300"
  }
}

run "alarm_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["error_rate"].evaluation_periods == 1
    error_message = "Default evaluation_periods must be 1"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["error_rate"].treat_missing_data == "notBreaching"
    error_message = "Default treat_missing_data must be notBreaching"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["error_rate"].datapoints_to_alarm == null
    error_message = "datapoints_to_alarm must stay unset by default"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["error_rate"].alarm_description == "Error rate is high. Check the application logs first."
    error_message = "alarm_description must follow description"
  }
}

run "alarm_and_ok_both_go_to_every_topic" {
  command = plan

  variables {
    sns_topic_arns = [
      "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms",
      "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-pager",
    ]
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(var.sns_topic_arns)])
    error_message = "Every alarm must send alarm_actions to all sns_topic_arns"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : a.ok_actions == toset(var.sns_topic_arns)])
    error_message = "Every alarm must send ok_actions to all sns_topic_arns"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.this : try(length(a.insufficient_data_actions), 0) == 0])
    error_message = "insufficient_data_actions must stay empty"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].tags == tomap({ Project = "alpha", Name = "alpha-dev-api-cpu-high" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "tags_default_to_name_only" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].tags == tomap({ Name = "alpha-dev-api-cpu-high" })
    error_message = "Without tags input the only alarm tag is Name"
  }
}

run "empty_alarms_creates_nothing" {
  command = plan

  variables {
    alarms = {}
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "alarms = {} must create nothing"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = toset(keys(output.alarm_arns)) == toset(["cpu_high", "error_rate"])
    error_message = "alarm_arns keys must equal the alarms keys"
  }

  assert {
    condition     = output.alarm_names["cpu_high"] == "alpha-dev-api-cpu-high" && output.alarm_names["error_rate"] == "alpha-dev-api-error-rate"
    error_message = "alarm_names must be keyed by the alarms keys and carry the alarm name"
  }
}

# ---- sns_topic_arns ----

run "rejects_empty_sns_topics" {
  command = plan

  variables {
    sns_topic_arns = []
  }

  expect_failures = [var.sns_topic_arns]
}

run "rejects_malformed_sns_topic" {
  command = plan

  variables {
    sns_topic_arns = ["not-an-arn"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "rejects_non_sns_arn" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-queue"]
  }

  expect_failures = [var.sns_topic_arns]
}

run "accepts_sns_topic_arn" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-pager"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].alarm_actions == toset(["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-pager"])
    error_message = "A well-formed SNS topic ARN must be accepted"
  }
}

# ---- name_prefix and keys ----

run "rejects_uppercase_name_prefix" {
  command = plan

  variables {
    name_prefix = "Alpha-dev"
  }

  expect_failures = [var.name_prefix]
}

run "accepts_lowercase_name_prefix" {
  command = plan

  variables {
    name_prefix = "alpha-sit"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu_high"].alarm_name == "alpha-sit-cpu-high"
    error_message = "A lowercase name_prefix must be accepted"
  }
}

run "rejects_key_not_snake_case" {
  command = plan

  variables {
    alarms = {
      CpuHigh = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_snake_case_key_with_digits" {
  command = plan

  variables {
    alarms = {
      a_1 = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a_1"].alarm_name == "alpha-dev-api-a-1"
    error_message = "A snake_case key with digits must be accepted"
  }
}

run "rejects_empty_description" {
  command = plan

  variables {
    alarms = {
      a = {
        description = " "
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}

# ---- metric xor queries ----

run "rejects_metric_and_queries_together" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_neither_metric_nor_queries" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_metric_only" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["a"].metric_query) == 0 && aws_cloudwatch_metric_alarm.this["a"].metric_name == "CPUUtilization"
    error_message = "metric alone must be accepted"
  }
}

run "accepts_queries_only" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["a"].metric_query) == 1
    error_message = "queries alone must be accepted"
  }
}

# ---- queries shape ----

run "rejects_queries_without_return_data" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" } },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_queries_with_two_return_data" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
          { id = "m2", metric = { namespace = "AWS/EC2", metric_name = "NetworkIn" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_query_with_expression_and_metric" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", expression = "1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_query_with_neither_expression_nor_metric" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_duplicate_query_ids" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" } },
          { id = "m1", expression = "m1 * 2", return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_query_id_starting_with_uppercase" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "M1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_query_id_camel_case_after_first_letter" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "errorRate1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }, return_data = true },
        ]
      }
    }
  }

  assert {
    condition     = [for q in aws_cloudwatch_metric_alarm.this["a"].metric_query : q.id] == ["errorRate1"]
    error_message = "A query id that starts lowercase must be accepted"
  }
}

# ---- statistic, operator, missing data, period, datapoints ----

run "rejects_unknown_statistic" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", statistic = "p99" }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_unknown_statistic_in_query_metric" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization", statistic = "Median" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_maximum_statistic" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", statistic = "Maximum" }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].statistic == "Maximum"
    error_message = "Maximum must be accepted"
  }
}

run "rejects_unknown_comparison_operator" {
  command = plan

  variables {
    alarms = {
      a = {
        description         = "d"
        threshold           = 1
        comparison_operator = "Equals"
        metric              = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_less_than_threshold" {
  command = plan

  variables {
    alarms = {
      a = {
        description         = "d"
        threshold           = 1
        comparison_operator = "LessThanThreshold"
        metric              = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].comparison_operator == "LessThanThreshold"
    error_message = "LessThanThreshold must be accepted"
  }
}

run "rejects_unknown_treat_missing_data" {
  command = plan

  variables {
    alarms = {
      a = {
        description        = "d"
        threshold          = 1
        treat_missing_data = "ok"
        metric             = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_breaching_treat_missing_data" {
  command = plan

  variables {
    alarms = {
      a = {
        description        = "d"
        threshold          = 1
        treat_missing_data = "breaching"
        metric             = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].treat_missing_data == "breaching"
    error_message = "breaching must be accepted"
  }
}

run "rejects_period_45" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", period = 45 }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "rejects_period_45_in_query_metric" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        queries = [
          { id = "m1", metric = { namespace = "AWS/EC2", metric_name = "CPUUtilization", period = 45 }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_period_10" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", period = 10 }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 10
    error_message = "Period 10 must be accepted"
  }
}

run "accepts_period_30" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", period = 30 }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 30
    error_message = "Period 30 must be accepted"
  }
}

run "accepts_period_120" {
  command = plan

  variables {
    alarms = {
      a = {
        description = "d"
        threshold   = 1
        metric      = { namespace = "AWS/EC2", metric_name = "CPUUtilization", period = 120 }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].period == 120
    error_message = "Period 120 must be accepted"
  }
}

run "rejects_datapoints_above_evaluation_periods" {
  command = plan

  variables {
    alarms = {
      a = {
        description         = "d"
        threshold           = 1
        evaluation_periods  = 2
        datapoints_to_alarm = 3
        metric              = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}

run "accepts_datapoints_equal_to_evaluation_periods" {
  command = plan

  variables {
    alarms = {
      a = {
        description         = "d"
        threshold           = 1
        evaluation_periods  = 2
        datapoints_to_alarm = 2
        metric              = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["a"].datapoints_to_alarm == 2
    error_message = "datapoints_to_alarm equal to evaluation_periods must be accepted"
  }
}

run "rejects_zero_evaluation_periods" {
  command = plan

  variables {
    alarms = {
      a = {
        description        = "d"
        threshold          = 1
        evaluation_periods = 0
        metric             = { namespace = "AWS/EC2", metric_name = "CPUUtilization" }
      }
    }
  }

  expect_failures = [var.alarms]
}
