mock_provider "aws" {}

variables {
  name_prefix    = "alpha-dev-api"
  log_group_name = "/ecs/alpha-dev-api"
  namespace      = "Alpha/dev"
}

run "metrics_only_creates_filters_without_alarms_or_sns" {
  command = plan

  variables {
    metrics = {
      request_total = {
        pattern     = "{ $.event = \"request\" }"
        metric_name = "RequestTotal"
      }
      slow_request = {
        pattern       = "{ $.duration_ms > 1000 }"
        metric_name   = "SlowRequest"
        metric_value  = "$.duration_ms"
        default_value = 5
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 2
    error_message = "Each metrics entry must create one metric filter"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "metrics must never create an alarm"
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["request_total"].name == "alpha-dev-api-request-total"
    error_message = "Metric filter name must be <name_prefix>-<key with _ replaced by ->"
  }

  assert {
    condition     = one(aws_cloudwatch_log_metric_filter.this["request_total"].metric_transformation).value == "1" && one(aws_cloudwatch_log_metric_filter.this["request_total"].metric_transformation).default_value == "0"
    error_message = "metrics must default to value 1 and default_value 0"
  }

  assert {
    condition     = one(aws_cloudwatch_log_metric_filter.this["slow_request"].metric_transformation).value == "$.duration_ms" && one(aws_cloudwatch_log_metric_filter.this["slow_request"].metric_transformation).default_value == "5"
    error_message = "metric_value and default_value must be applied"
  }

  assert {
    condition     = one(aws_cloudwatch_log_metric_filter.this["request_total"].metric_transformation).namespace == "Alpha/dev" && aws_cloudwatch_log_metric_filter.this["request_total"].log_group_name == "/ecs/alpha-dev-api"
    error_message = "metrics must use the shared namespace and log group"
  }
}

run "alarms_and_metrics_coexist" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    alarms = {
      write_failed = {
        pattern     = "ERROR"
        metric_name = "WriteFailed"
        description = "Writes failed. Check the database first."
      }
    }
    metrics = {
      request_total = {
        pattern     = "{ $.event = \"request\" }"
        metric_name = "RequestTotal"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 2 && length(aws_cloudwatch_metric_alarm.this) == 1
    error_message = "Two filters and one alarm expected"
  }

  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.this), "request_total") == false
    error_message = "A metrics key must not get an alarm"
  }
}

run "alarms_without_sns_rejected" {
  command = plan

  variables {
    alarms = {
      write_failed = {
        pattern     = "ERROR"
        metric_name = "WriteFailed"
        description = "d"
      }
    }
    metrics = {
      request_total = {
        pattern     = "{ $.event = \"request\" }"
        metric_name = "RequestTotal"
      }
    }
  }

  expect_failures = [var.sns_topic_arns]
}

run "malformed_sns_rejected_even_without_alarms" {
  command = plan

  variables {
    sns_topic_arns = ["not-an-arn"]
    metrics = {
      request_total = {
        pattern     = "ERROR"
        metric_name = "RequestTotal"
      }
    }
  }

  expect_failures = [var.sns_topic_arns]
}

run "same_key_in_alarms_and_metrics_rejected" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    alarms = {
      write_failed = {
        pattern     = "ERROR"
        metric_name = "WriteFailed"
        description = "d"
      }
    }
    metrics = {
      write_failed = {
        pattern     = "ERROR"
        metric_name = "WriteFailedCount"
      }
    }
  }

  expect_failures = [var.metrics]
}

run "nothing_given_rejected" {
  command = plan

  expect_failures = [var.metrics]
}

run "empty_alarms_and_metrics_with_sns_still_creates_nothing" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    alarms         = {}
    metrics        = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 0 && length(aws_cloudwatch_metric_alarm.this) == 0
    error_message = "Existing alarms = {} behavior must stay: nothing is created"
  }
}

run "metrics_key_must_be_snake_case" {
  command = plan

  variables {
    metrics = {
      RequestTotal = {
        pattern     = "ERROR"
        metric_name = "RequestTotal"
      }
    }
  }

  expect_failures = [var.metrics]
}

run "metrics_pattern_must_not_be_blank" {
  command = plan

  variables {
    metrics = {
      request_total = {
        pattern     = " "
        metric_name = "RequestTotal"
      }
    }
  }

  expect_failures = [var.metrics]
}

run "metric_names_output_covers_alarms_and_metrics" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    alarms = {
      write_failed = {
        pattern     = "ERROR"
        metric_name = "WriteFailed"
        description = "d"
      }
    }
    metrics = {
      request_total = {
        pattern     = "{ $.event = \"request\" }"
        metric_name = "RequestTotal"
      }
    }
  }

  assert {
    condition     = output.metric_names == { write_failed = "WriteFailed", request_total = "RequestTotal" }
    error_message = "metric_names must map every alarms and metrics key to its metric name"
  }
}

run "metric_names_output_empty_when_nothing_created" {
  command = plan

  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    alarms         = {}
  }

  assert {
    condition     = length(output.metric_names) == 0
    error_message = "metric_names must be empty when no filter is created"
  }
}
