mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-raw"
    bucket                      = "alpha-dev-raw"
    bucket_regional_domain_name = "alpha-dev-raw.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name = "alpha-dev-raw"
}

# ---- transitions ----------------------------------------------------------------------------------------------

run "no_transitions_by_default" {
  command = plan

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).transition) == 0
    error_message = "Without transitions the rule must have no transition block"
  }
}

run "transitions_land_in_the_current_version_rule" {
  command = plan

  variables {
    expiration_days = 365
    transitions = [
      { days = 30, storage_class = "STANDARD_IA" },
      { days = 90, storage_class = "GLACIER_IR" },
    ]
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "expire-objects"
    error_message = "The single rule must stay expire-objects"
  }

  assert {
    condition = toset([
      for t in one(aws_s3_bucket_lifecycle_configuration.this.rule).transition : "${t.storage_class}:${t.days}"
    ]) == toset(["STANDARD_IA:30", "GLACIER_IR:90"])
    error_message = "Both transitions must be written with their storage class and days"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 365
    error_message = "The expiration must be kept next to the transitions"
  }
}

run "transitions_do_not_touch_the_noncurrent_cleanup_rule" {
  command = plan

  variables {
    versioning = {}
    transitions = [
      { days = 30, storage_class = "STANDARD_IA" },
    ]
  }

  assert {
    condition = length(one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "expire-objects"
    ]).transition) == 1
    error_message = "The current-version rule must carry the transition"
  }

  assert {
    condition = length(one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "cleanup-noncurrent-versions"
    ]).transition) == 0
    error_message = "The noncurrent cleanup rule must not get transitions"
  }
}

run "transitions_work_with_never_expire" {
  command = plan

  variables {
    never_expire = true
    transitions = [
      { days = 30, storage_class = "STANDARD_IA" },
      { days = 365, storage_class = "DEEP_ARCHIVE" },
    ]
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "abort-incomplete-uploads"
    error_message = "never_expire keeps its rule id"
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).transition) == 2
    error_message = "Transitions are allowed when nothing expires"
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration) == 0
    error_message = "never_expire must still produce no expiration"
  }
}

run "transition_days_must_increase" {
  command = plan

  variables {
    transitions = [
      { days = 60, storage_class = "STANDARD_IA" },
      { days = 30, storage_class = "GLACIER_IR" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_equal_days_rejected" {
  command = plan

  variables {
    transitions = [
      { days = 30, storage_class = "STANDARD_IA" },
      { days = 30, storage_class = "GLACIER_IR" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_days_must_be_below_explicit_expiration" {
  command = plan

  variables {
    expiration_days = 60
    transitions = [
      { days = 60, storage_class = "STANDARD_IA" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_days_must_be_below_default_expiration" {
  command = plan

  # expiration_days is unset, so the module expires at 90 days.
  variables {
    transitions = [
      { days = 90, storage_class = "GLACIER_IR" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_last_day_before_expiration_is_accepted" {
  command = plan

  variables {
    expiration_days = 91
    transitions = [
      { days = 90, storage_class = "GLACIER_IR" },
    ]
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).transition) == 1
    error_message = "A transition one day before expiration is valid"
  }
}

run "transition_storage_class_must_be_a_target_class" {
  command = plan

  variables {
    transitions = [
      { days = 30, storage_class = "STANDARD" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_storage_class_is_case_sensitive" {
  command = plan

  variables {
    transitions = [
      { days = 30, storage_class = "standard_ia" },
    ]
  }

  expect_failures = [var.transitions]
}

run "transition_days_must_be_positive" {
  command = plan

  variables {
    transitions = [
      { days = 0, storage_class = "STANDARD_IA" },
    ]
  }

  expect_failures = [var.transitions]
}

# ---- eventbridge ----------------------------------------------------------------------------------------------

run "no_new_variables_keeps_the_0_3_1_behaviour" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "Without lambda_notifications and eventbridge there must be no notification resource"
  }
}

run "eventbridge_alone_creates_the_notification" {
  command = plan

  variables {
    eventbridge = true
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 1
    error_message = "eventbridge = true must create the notification resource"
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == true
    error_message = "The notification must have eventbridge enabled"
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].lambda_function) == 0
    error_message = "No lambda_function block without lambda_notifications"
  }
}

run "eventbridge_coexists_with_lambda_notifications" {
  command = plan

  variables {
    eventbridge = true
    lambda_notifications = {
      thumbnails = { function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-thumbnails" }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 1
    error_message = "Both together must still be one notification resource"
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == true
    error_message = "eventbridge must stay enabled next to Lambda targets"
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].lambda_function) == 1
    error_message = "The Lambda target must still be written"
  }
}

run "lambda_only_leaves_eventbridge_off" {
  command = plan

  variables {
    lambda_notifications = {
      thumbnails = { function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-thumbnails" }
    }
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge == false
    error_message = "eventbridge must default to false"
  }
}

run "eventbridge_false_creates_nothing" {
  command = plan

  variables {
    eventbridge = false
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "An explicit false must behave like the default"
  }
}
