mock_provider "aws" {}

override_resource {
  target          = aws_scheduler_schedule.this
  override_during = plan
  values = {
    arn = "arn:aws:scheduler:ap-northeast-1:111111111111:schedule/default/alpha-dev-retrain"
  }
}

override_resource {
  target          = aws_scheduler_schedule_group.this
  override_during = plan
  values = {
    arn = "arn:aws:scheduler:ap-northeast-1:111111111111:schedule-group/alpha-dev-ml"
  }
}

variables {
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  schedules = {
    alpha-dev-retrain = {
      expression = "cron(0 3 ? * MON *)"
      target = {
        arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
        role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        sagemaker_pipeline_parameters = {
          InputPrefix = "s3://alpha-dev-ml-artifacts/datasets/"
          Epochs      = "10"
        }
      }
    }
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "cron_with_sagemaker_pipeline_parameters" {
  command = plan

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-retrain"].name == "alpha-dev-retrain" && aws_scheduler_schedule.this["alpha-dev-retrain"].schedule_expression == "cron(0 3 ? * MON *)"
    error_message = "The name is the map key and the expression is passed through"
  }

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-retrain"].schedule_expression_timezone == "Asia/Taipei" && aws_scheduler_schedule.this["alpha-dev-retrain"].state == "ENABLED"
    error_message = "Timezone must default to Asia/Taipei and state to ENABLED"
  }

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-retrain"].group_name == "default"
    error_message = "Schedules go to the default group when group_name is null"
  }

  assert {
    condition     = one(aws_scheduler_schedule.this["alpha-dev-retrain"].flexible_time_window).mode == "OFF" && one(aws_scheduler_schedule.this["alpha-dev-retrain"].flexible_time_window).maximum_window_in_minutes == null
    error_message = "A null flexible window means mode OFF"
  }

  assert {
    condition     = one(aws_scheduler_schedule.this["alpha-dev-retrain"].target).arn == "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train" && one(aws_scheduler_schedule.this["alpha-dev-retrain"].target).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
    error_message = "Target ARN and role must be passed through"
  }

  assert {
    condition = toset([
      for p in one(one(aws_scheduler_schedule.this["alpha-dev-retrain"].target).sagemaker_pipeline_parameters).pipeline_parameter : "${p.name}=${p.value}"
    ]) == toset(["InputPrefix=s3://alpha-dev-ml-artifacts/datasets/", "Epochs=10"])
    error_message = "SageMaker pipeline parameters must be passed through"
  }

  assert {
    condition     = length(aws_scheduler_schedule_group.this) == 0
    error_message = "No schedule group may be created when group_name is null"
  }
}

run "schedules_are_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-retrain"].kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Schedules must use the given CMK"
  }
}

run "flexible_window_and_rate" {
  command = plan

  variables {
    schedules = {
      alpha-dev-report = {
        expression              = "rate(1 hour)"
        timezone                = "UTC"
        state                   = "DISABLED"
        flexible_window_minutes = 15
        target = {
          arn      = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-report"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
          input    = "{\"report\":\"daily\"}"
        }
      }
    }
  }

  assert {
    condition     = one(aws_scheduler_schedule.this["alpha-dev-report"].flexible_time_window).mode == "FLEXIBLE" && one(aws_scheduler_schedule.this["alpha-dev-report"].flexible_time_window).maximum_window_in_minutes == 15
    error_message = "A flexible window means mode FLEXIBLE with the given minutes"
  }

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-report"].schedule_expression_timezone == "UTC" && aws_scheduler_schedule.this["alpha-dev-report"].state == "DISABLED"
    error_message = "timezone and state must be passed through"
  }

  assert {
    condition     = one(aws_scheduler_schedule.this["alpha-dev-report"].target).input == "{\"report\":\"daily\"}"
    error_message = "input must be passed through"
  }

  assert {
    condition     = length(one(aws_scheduler_schedule.this["alpha-dev-report"].target).sagemaker_pipeline_parameters) == 0
    error_message = "No SageMaker parameters block without parameters"
  }
}

run "one_time_schedule_with_dead_letter_and_retry" {
  command = plan

  variables {
    schedules = {
      alpha-dev-once = {
        expression = "at(2026-12-01T03:00:00)"
        target = {
          arn             = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-report"
          role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
          dead_letter_arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-scheduler-dlq"
          retry = {
            maximum_event_age_seconds = 3600
            maximum_retry_attempts    = 3
          }
        }
      }
    }
  }

  assert {
    condition     = one(one(aws_scheduler_schedule.this["alpha-dev-once"].target).dead_letter_config).arn == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-scheduler-dlq"
    error_message = "dead_letter_arn must be passed through"
  }

  assert {
    condition     = one(one(aws_scheduler_schedule.this["alpha-dev-once"].target).retry_policy).maximum_event_age_in_seconds == 3600 && one(one(aws_scheduler_schedule.this["alpha-dev-once"].target).retry_policy).maximum_retry_attempts == 3
    error_message = "retry must be passed through"
  }
}

run "schedule_group" {
  command = plan

  variables {
    group_name = "alpha-dev-ml"
    tags       = { Project = "alpha" }
  }

  assert {
    condition     = aws_scheduler_schedule_group.this[0].name == "alpha-dev-ml"
    error_message = "The schedule group must be created with group_name"
  }

  assert {
    condition     = aws_scheduler_schedule.this["alpha-dev-retrain"].group_name == "alpha-dev-ml"
    error_message = "Schedules must go to the created group"
  }

  assert {
    condition     = aws_scheduler_schedule_group.this[0].tags["Project"] == "alpha" && aws_scheduler_schedule_group.this[0].tags["Name"] == "alpha-dev-ml"
    error_message = "Name must be added to the group tags"
  }
}

run "no_schedules" {
  command = plan

  variables {
    schedules = {}
  }

  assert {
    condition     = length(aws_scheduler_schedule.this) == 0 && output.schedule_arns == {}
    error_message = "An empty map creates nothing"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.schedule_arns == { alpha-dev-retrain = "arn:aws:scheduler:ap-northeast-1:111111111111:schedule/default/alpha-dev-retrain" }
    error_message = "schedule_arns must map schedule names to ARNs"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "expression_format_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "every monday"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "expression_with_unknown_prefix_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "daily(03:00)"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "flexible_window_zero_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression              = "rate(1 day)"
        flexible_window_minutes = 0
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "flexible_window_above_1440_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression              = "rate(1 day)"
        flexible_window_minutes = 1441
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "missing_role_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = null
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "role_arn_format_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "target_arn_format_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn      = "alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "pipeline_parameters_on_a_non_pipeline_target_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn                           = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-report"
          role_arn                      = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
          sagemaker_pipeline_parameters = { Epochs = "10" }
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "dead_letter_not_sqs_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn             = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn        = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
          dead_letter_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alerts"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "retry_attempts_above_185_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
          retry    = { maximum_retry_attempts = 186 }
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "invalid_state_rejected" {
  command = plan

  variables {
    schedules = {
      alpha-dev-retrain = {
        expression = "rate(1 day)"
        state      = "PAUSED"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "invalid_schedule_name_rejected" {
  command = plan

  variables {
    schedules = {
      "alpha dev/retrain" = {
        expression = "rate(1 day)"
        target = {
          arn      = "arn:aws:sagemaker:ap-northeast-1:111111111111:pipeline/alpha-dev-train"
          role_arn = "arn:aws:iam::111111111111:role/alpha-dev-scheduler"
        }
      }
    }
  }

  expect_failures = [var.schedules]
}

run "default_group_name_rejected" {
  command = plan

  variables {
    group_name = "default"
  }

  expect_failures = [var.group_name]
}

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}
