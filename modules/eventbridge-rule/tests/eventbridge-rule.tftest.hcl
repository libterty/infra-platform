mock_provider "aws" {}

override_resource {
  target          = aws_cloudwatch_event_rule.this
  override_during = plan
  values = {
    arn = "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-model-approved"
  }
}

variables {
  name = "alpha-dev-model-approved"

  event_pattern = {
    source        = ["aws.sagemaker"]
    "detail-type" = ["SageMaker Model Package State Change"]
    detail = {
      ModelPackageGroupName = ["alpha-dev-models"]
      ModelApprovalStatus   = ["Approved"]
    }
  }

  targets = {
    queue = {
      arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "pattern_with_sqs_target" {
  command = plan

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.this.event_pattern) == {
      source        = ["aws.sagemaker"]
      "detail-type" = ["SageMaker Model Package State Change"]
      detail = {
        ModelPackageGroupName = ["alpha-dev-models"]
        ModelApprovalStatus   = ["Approved"]
      }
    }
    error_message = "The event pattern object must be JSON-encoded as given"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.schedule_expression == null
    error_message = "A pattern rule must not have a schedule"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.event_bus_name == "default" && aws_cloudwatch_event_rule.this.state == "ENABLED"
    error_message = "The rule must default to the default bus and ENABLED"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["queue"].arn == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
    error_message = "The target ARN must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["queue"].target_id == "queue" && aws_cloudwatch_event_target.this["queue"].rule == "alpha-dev-model-approved"
    error_message = "The target id is the map key and the target belongs to the rule"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["queue"].role_arn == null
    error_message = "An SQS target needs no role"
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this["queue"].dead_letter_config) == 0 && length(aws_cloudwatch_event_target.this["queue"].retry_policy) == 0 && length(aws_cloudwatch_event_target.this["queue"].input_transformer) == 0
    error_message = "Optional target blocks must be absent when not given"
  }
}

run "schedule_with_a_target_that_needs_a_role" {
  command = plan

  variables {
    event_pattern       = null
    schedule_expression = "rate(1 day)"
    state               = "DISABLED"
    targets = {
      pipeline = {
        arn      = "arn:aws:states:ap-northeast-1:111111111111:stateMachine:alpha-dev-retrain"
        role_arn = "arn:aws:iam::111111111111:role/alpha-dev-events-invoke"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.schedule_expression == "rate(1 day)" && aws_cloudwatch_event_rule.this.event_pattern == null
    error_message = "A schedule rule must not have a pattern"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.state == "DISABLED"
    error_message = "state must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["pipeline"].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-events-invoke"
    error_message = "role_arn must be passed through"
  }
}

run "input_transformer" {
  command = plan

  variables {
    targets = {
      queue = {
        arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        input_transformer = {
          input_paths    = { arn = "$.detail.ModelPackageArn" }
          input_template = "{\"model_package_arn\": <arn>}"
        }
      }
    }
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this["queue"].input_transformer).input_paths == tomap({ arn = "$.detail.ModelPackageArn" })
    error_message = "input_paths must be passed through"
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this["queue"].input_transformer).input_template == "{\"model_package_arn\": <arn>}"
    error_message = "input_template must be passed through"
  }
}

run "dead_letter_queue_and_retry" {
  command = plan

  variables {
    targets = {
      queue = {
        arn             = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        dead_letter_arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-events-dlq"
        retry = {
          maximum_event_age_seconds = 3600
          maximum_retry_attempts    = 10
        }
      }
    }
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this["queue"].dead_letter_config).arn == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-events-dlq"
    error_message = "dead_letter_arn must be passed through"
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this["queue"].retry_policy).maximum_event_age_in_seconds == 3600 && one(aws_cloudwatch_event_target.this["queue"].retry_policy).maximum_retry_attempts == 10
    error_message = "retry must be passed through"
  }
}

run "fifo_queue_target_with_message_group" {
  command = plan

  variables {
    targets = {
      queue = {
        arn                  = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved.fifo"
        sqs_message_group_id = "models"
      }
    }
  }

  assert {
    condition     = one(aws_cloudwatch_event_target.this["queue"].sqs_target).message_group_id == "models"
    error_message = "sqs_message_group_id must be passed through"
  }
}

run "sns_and_lambda_targets_need_no_role" {
  command = plan

  variables {
    targets = {
      topic  = { arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alerts" }
      lambda = { arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-notify" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this) == 2
    error_message = "Every target must be created"
  }

  assert {
    condition     = alltrue([for t in aws_cloudwatch_event_target.this : t.role_arn == null])
    error_message = "SNS and Lambda targets need no role"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this.tags["Project"] == "alpha" && aws_cloudwatch_event_rule.this.tags["Name"] == "alpha-dev-model-approved"
    error_message = "Name must be added to the given tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.rule_arn == "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-model-approved"
    error_message = "rule_arn output must be the rule ARN"
  }

  assert {
    condition     = output.rule_name == "alpha-dev-model-approved"
    error_message = "rule_name output must be the rule name"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "pattern_and_schedule_both_rejected" {
  command = plan

  variables {
    schedule_expression = "rate(1 day)"
  }

  expect_failures = [var.schedule_expression]
}

run "neither_pattern_nor_schedule_rejected" {
  command = plan

  variables {
    event_pattern = null
  }

  expect_failures = [var.schedule_expression]
}

run "schedule_format_rejected" {
  command = plan

  variables {
    event_pattern       = null
    schedule_expression = "every day"
  }

  expect_failures = [var.schedule_expression]
}

run "schedule_on_a_custom_bus_rejected" {
  command = plan

  variables {
    event_pattern       = null
    schedule_expression = "rate(1 day)"
    event_bus_name      = "alpha-dev-bus"
  }

  expect_failures = [var.schedule_expression]
}

run "no_target_rejected" {
  command = plan

  variables {
    targets = {}
  }

  expect_failures = [var.targets]
}

run "more_than_five_targets_rejected" {
  command = plan

  variables {
    targets = {
      t1 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q1" }
      t2 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q2" }
      t3 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q3" }
      t4 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q4" }
      t5 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q5" }
      t6 = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:q6" }
    }
  }

  expect_failures = [var.targets]
}

run "target_without_required_role_rejected" {
  command = plan

  variables {
    targets = {
      pipeline = { arn = "arn:aws:states:ap-northeast-1:111111111111:stateMachine:alpha-dev-retrain" }
    }
  }

  expect_failures = [var.targets]
}

run "role_arn_format_rejected" {
  command = plan

  variables {
    targets = {
      pipeline = {
        arn      = "arn:aws:states:ap-northeast-1:111111111111:stateMachine:alpha-dev-retrain"
        role_arn = "alpha-dev-events-invoke"
      }
    }
  }

  expect_failures = [var.targets]
}

run "target_arn_format_rejected" {
  command = plan

  variables {
    targets = {
      queue = { arn = "alpha-dev-model-approved" }
    }
  }

  expect_failures = [var.targets]
}

run "dead_letter_not_sqs_rejected" {
  command = plan

  variables {
    targets = {
      queue = {
        arn             = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        dead_letter_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alerts"
      }
    }
  }

  expect_failures = [var.targets]
}

run "retry_event_age_below_60_rejected" {
  command = plan

  variables {
    targets = {
      queue = {
        arn   = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        retry = { maximum_event_age_seconds = 59 }
      }
    }
  }

  expect_failures = [var.targets]
}

run "retry_attempts_above_185_rejected" {
  command = plan

  variables {
    targets = {
      queue = {
        arn   = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        retry = { maximum_retry_attempts = 186 }
      }
    }
  }

  expect_failures = [var.targets]
}

run "fifo_target_without_message_group_rejected" {
  command = plan

  variables {
    targets = {
      queue = { arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved.fifo" }
    }
  }

  expect_failures = [var.targets]
}

run "message_group_on_a_standard_queue_rejected" {
  command = plan

  variables {
    targets = {
      queue = {
        arn                  = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
        sqs_message_group_id = "models"
      }
    }
  }

  expect_failures = [var.targets]
}

run "invalid_state_rejected" {
  command = plan

  variables {
    state = "PAUSED"
  }

  expect_failures = [var.state]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha dev/model"
  }

  expect_failures = [var.name]
}
