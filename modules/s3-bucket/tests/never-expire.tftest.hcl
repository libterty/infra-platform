mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-flow-logs"
    bucket                      = "alpha-dev-flow-logs"
    bucket_regional_domain_name = "alpha-dev-flow-logs.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name = "alpha-dev-flow-logs"
}

run "never_expire_drops_expiration" {
  command = plan

  variables {
    never_expire = true
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration) == 0
    error_message = "never_expire must remove the expiration block"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must still be aborted after 7 days"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "abort-incomplete-uploads"
    error_message = "Rule id must be abort-incomplete-uploads when objects never expire"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).status == "Enabled"
    error_message = "The lifecycle rule must stay enabled"
  }
}

# The existing test file does not pin the rule id; changing it would show a diff on existing buckets.
run "default_keeps_expire_rule" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "expire-objects"
    error_message = "Default rule id must stay expire-objects"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "Default expiration must be 90 days"
  }
}

run "explicit_null_days_means_90" {
  command = plan

  variables {
    expiration_days = null
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "expiration_days = null must mean 90 days, not never expire"
  }
}

run "null_never_expire_means_false" {
  command = plan

  variables {
    never_expire = null
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "never_expire = null must behave as false"
  }
}

run "days_without_never_expire" {
  command = plan

  variables {
    never_expire    = false
    expiration_days = 30
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 30
    error_message = "expiration_days must apply when never_expire is false"
  }
}

run "never_expire_rejects_expiration_days" {
  command = plan

  variables {
    never_expire    = true
    expiration_days = 30
  }

  expect_failures = [var.never_expire]
}

run "never_expire_rejects_flow_log_delivery" {
  command = plan

  variables {
    never_expire = true
    log_delivery = ["vpc_flow_logs"]
  }

  expect_failures = [var.never_expire]
}

run "never_expire_rejects_log_delivery" {
  command = plan

  variables {
    never_expire = true
    log_delivery = ["vended_logs"]
  }

  expect_failures = [var.never_expire]
}

run "never_expire_accepts_empty_log_delivery" {
  command = plan

  variables {
    never_expire = true
    log_delivery = []
  }

  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration) == 0
    error_message = "never_expire with no log delivery must be accepted"
  }
}

run "log_delivery_keeps_expiration" {
  command = plan

  variables {
    log_delivery = ["vpc_flow_logs"]
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "Log buckets must keep the 90-day default expiration"
  }
}
