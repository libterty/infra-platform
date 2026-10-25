mock_provider "aws" {}

variables {
  rules = {
    telemetry = {
      sql = "SELECT * FROM 'alpha/dev/+/telemetry'"
      actions = {
        kinesis = [{
          stream_name   = "alpha-dev-telemetry"
          role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
          partition_key = "$${topic(3)}"
        }]
      }
    }
  }
  error_action = {
    sqs = {
      queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-iot-errors"
      role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "single_rule_with_defaults" {
  command = plan

  assert {
    condition     = aws_iot_topic_rule.this["telemetry"].name == "telemetry"
    error_message = "The map key must be the rule name"
  }
  assert {
    condition     = aws_iot_topic_rule.this["telemetry"].sql_version == "2016-03-23"
    error_message = "sql_version must be fixed to 2016-03-23"
  }
  assert {
    condition     = aws_iot_topic_rule.this["telemetry"].enabled == true
    error_message = "Rules must default to enabled"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["telemetry"].kinesis).stream_name == "alpha-dev-telemetry" && one(aws_iot_topic_rule.this["telemetry"].kinesis).partition_key == "$${topic(3)}"
    error_message = "The kinesis action must be passed through"
  }
  assert {
    condition     = one(one(aws_iot_topic_rule.this["telemetry"].error_action).sqs).queue_url == "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-iot-errors"
    error_message = "The error action must be attached to every rule"
  }
  assert {
    condition     = one(one(aws_iot_topic_rule.this["telemetry"].error_action).sqs).use_base64 == false
    error_message = "sqs.use_base64 must default to false"
  }
  assert {
    condition     = length(one(aws_iot_topic_rule.this["telemetry"].error_action).kinesis) == 0 && length(aws_iot_topic_rule.this["telemetry"].sqs) == 0
    error_message = "Only the configured actions may be present"
  }
}

run "many_rules_and_every_action" {
  command = plan

  variables {
    rules = {
      telemetry = {
        sql         = "SELECT * FROM 'alpha/dev/+/telemetry'"
        description = "telemetry to Kinesis and S3"
        actions = {
          kinesis = [{ stream_name = "alpha-dev-telemetry", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          s3      = [{ bucket_name = "alpha-dev-raw", key = "iot/$${topic()}/$${timestamp()}.json", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
        }
      }
      results = {
        sql     = "select deviceId, label FROM 'alpha/dev/+/inference'"
        enabled = false
        actions = {
          firehose          = [{ delivery_stream_name = "alpha-dev-results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule", separator = "\n", batch_mode = true }]
          sqs               = [{ queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          lambda            = [{ function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-results" }]
          dynamodbv2        = [{ table_name = "alpha-dev-results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          republish         = [{ topic = "alpha/dev/results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          cloudwatch_logs   = [{ log_group_name = "/alpha/dev/iot-results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          cloudwatch_metric = [{ metric_name = "Results", metric_namespace = "Alpha/IoT", metric_unit = "Count", metric_value = "1", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
          sns               = [{ target_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-results", role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule" }]
        }
      }
    }
    tags = { Project = "alpha" }
  }

  assert {
    condition     = length(aws_iot_topic_rule.this) == 2
    error_message = "One rule per map entry"
  }
  assert {
    condition     = alltrue([for r in aws_iot_topic_rule.this : r.sql_version == "2016-03-23"])
    error_message = "Every rule must use sql_version 2016-03-23"
  }
  assert {
    condition     = aws_iot_topic_rule.this["results"].enabled == false && aws_iot_topic_rule.this["telemetry"].description == "telemetry to Kinesis and S3"
    error_message = "enabled and description must be passed through"
  }
  assert {
    condition     = length(aws_iot_topic_rule.this["telemetry"].kinesis) == 1 && one(aws_iot_topic_rule.this["telemetry"].s3).bucket_name == "alpha-dev-raw"
    error_message = "kinesis and s3 actions must be passed through"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["results"].firehose).batch_mode == true && one(aws_iot_topic_rule.this["results"].firehose).separator == "\n"
    error_message = "firehose options must be passed through"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["results"].lambda).function_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-results"
    error_message = "lambda action must be passed through"
  }
  assert {
    condition     = one(one(aws_iot_topic_rule.this["results"].dynamodbv2).put_item).table_name == "alpha-dev-results"
    error_message = "dynamodbv2 action must write to the given table"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["results"].republish).qos == 0
    error_message = "republish qos must default to 0"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["results"].cloudwatch_logs).log_group_name == "/alpha/dev/iot-results" && one(aws_iot_topic_rule.this["results"].cloudwatch_metric).metric_unit == "Count"
    error_message = "cloudwatch actions must be passed through"
  }
  assert {
    condition     = one(aws_iot_topic_rule.this["results"].sns).message_format == "RAW" && length(aws_iot_topic_rule.this["results"].sqs) == 1
    error_message = "sns message_format must default to RAW and sqs must be passed through"
  }
  assert {
    condition     = aws_iot_topic_rule.this["telemetry"].tags["Project"] == "alpha" && aws_iot_topic_rule.this["telemetry"].tags["Name"] == "telemetry"
    error_message = "Name must be added to the given tags"
  }
}

run "error_action_cloudwatch_logs" {
  command = plan

  variables {
    error_action = {
      cloudwatch_logs = {
        log_group_name = "/alpha/dev/iot-errors"
        role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
      }
    }
  }

  assert {
    condition     = one(one(aws_iot_topic_rule.this["telemetry"].error_action).cloudwatch_logs).log_group_name == "/alpha/dev/iot-errors"
    error_message = "Any allowed action type can be the error action"
  }
}

run "outputs_after_apply" {
  command = apply

  override_resource {
    target = aws_iot_topic_rule.this["telemetry"]
    values = {
      arn = "arn:aws:iot:ap-northeast-1:111111111111:rule/telemetry"
    }
  }

  assert {
    condition     = output.rule_arns == { telemetry = "arn:aws:iot:ap-northeast-1:111111111111:rule/telemetry" }
    error_message = "rule_arns must map rule names to ARNs"
  }
  assert {
    condition     = output.rule_names == ["telemetry"]
    error_message = "rule_names must list the rule names"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "rule_without_action_rejected" {
  command = plan

  variables {
    rules = {
      telemetry = {
        sql     = "SELECT * FROM 'alpha/dev/+/telemetry'"
        actions = {}
      }
    }
  }

  expect_failures = [var.rules]
}

run "error_action_with_no_action_rejected" {
  command = plan

  variables {
    error_action = {}
  }

  expect_failures = [var.error_action]
}

run "error_action_with_two_actions_rejected" {
  command = plan

  variables {
    error_action = {
      sqs = {
        queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-iot-errors"
        role_arn  = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
      }
      cloudwatch_logs = {
        log_group_name = "/alpha/dev/iot-errors"
        role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-iot-rule"
      }
    }
  }

  expect_failures = [var.error_action]
}

run "rule_name_with_hyphen_rejected" {
  command = plan

  variables {
    rules = {
      "alpha-telemetry" = {
        sql     = "SELECT * FROM 'alpha/dev/+/telemetry'"
        actions = { lambda = [{ function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-results" }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "sql_not_select_rejected" {
  command = plan

  variables {
    rules = {
      telemetry = {
        sql     = "DELETE FROM 'alpha/dev/+/telemetry'"
        actions = { lambda = [{ function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-results" }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "rule_role_arn_format_rejected" {
  command = plan

  variables {
    rules = {
      telemetry = {
        sql     = "SELECT * FROM 'alpha/dev/+/telemetry'"
        actions = { kinesis = [{ stream_name = "alpha-dev-telemetry", role_arn = "alpha-dev-iot-rule" }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "error_action_role_arn_format_rejected" {
  command = plan

  variables {
    error_action = {
      sqs = {
        queue_url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-iot-errors"
        role_arn  = "arn:aws:iam::111111111111:user/alpha"
      }
    }
  }

  expect_failures = [var.error_action]
}

run "lambda_arn_format_rejected" {
  command = plan

  variables {
    rules = {
      telemetry = {
        sql     = "SELECT * FROM 'alpha/dev/+/telemetry'"
        actions = { lambda = [{ function_arn = "alpha-dev-results" }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "error_action_lambda_arn_format_rejected" {
  command = plan

  variables {
    error_action = {
      lambda = { function_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-results" }
    }
  }

  expect_failures = [var.error_action]
}
