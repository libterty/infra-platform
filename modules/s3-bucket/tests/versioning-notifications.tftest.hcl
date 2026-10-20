mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::111122223333:root" }
  }
}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-uploads"
    bucket                      = "alpha-dev-uploads"
    bucket_regional_domain_name = "alpha-dev-uploads.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name = "alpha-dev-uploads"
}

run "defaults_create_no_versioning_and_no_notification" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0
    error_message = "No versioning resource by default"
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 0
    error_message = "No notification resource by default"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "Without versioning the lifecycle keeps its single rule"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).id == "expire-objects"
    error_message = "The default rule id must stay expire-objects"
  }

  # filter.prefix is optional+computed, so a null prefix is unknown in plan and cannot be asserted; the block
  # itself must still be emitted because the provider requires a filter or prefix.
  assert {
    condition     = length(one(aws_s3_bucket_lifecycle_configuration.this.rule).filter) == 1
    error_message = "The default rule must keep its (empty) filter block"
  }
}

run "versioning_enabled_with_default_noncurrent_days" {
  command = plan

  variables {
    versioning = {}
  }

  assert {
    condition     = aws_s3_bucket_versioning.this[0].versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be Enabled"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "Versioning must add one lifecycle rule"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "expire-objects"]) != null
    error_message = "The current-version expiration rule must be kept"
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "cleanup-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after 30 days by default"
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "cleanup-noncurrent-versions"
    ]).expiration).expired_object_delete_marker == true
    error_message = "Expired delete markers must be cleaned up"
  }
}

run "versioning_custom_noncurrent_days" {
  command = plan

  variables {
    versioning = { noncurrent_expiration_days = 7 }
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "cleanup-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 7
    error_message = "noncurrent_expiration_days must be applied"
  }
}

run "versioning_with_never_expire_keeps_noncurrent_cleanup" {
  command = plan

  variables {
    versioning   = {}
    never_expire = true
  }

  assert {
    condition     = length(one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "abort-incomplete-uploads"]).expiration) == 0
    error_message = "never_expire must still drop the current-version expiration"
  }

  assert {
    condition     = length(one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "cleanup-noncurrent-versions"]).noncurrent_version_expiration) == 1
    error_message = "Noncurrent cleanup must stay with never_expire"
  }
}

run "versioning_noncurrent_days_3650_accepted" {
  command = plan

  variables {
    versioning = { noncurrent_expiration_days = 3650 }
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 1
    error_message = "3650 days must be accepted"
  }
}

run "versioning_noncurrent_days_3651_rejected" {
  command = plan

  variables {
    versioning = { noncurrent_expiration_days = 3651 }
  }

  expect_failures = [var.versioning]
}

run "versioning_noncurrent_days_0_rejected" {
  command = plan

  variables {
    versioning = { noncurrent_expiration_days = 0 }
  }

  expect_failures = [var.versioning]
}

run "versioning_with_log_delivery_rejected" {
  command = plan

  variables {
    versioning   = {}
    log_delivery = ["vpc_flow_logs"]
  }

  expect_failures = [var.versioning]
}

run "log_delivery_without_versioning_accepted" {
  command = plan

  variables {
    log_delivery = ["vpc_flow_logs"]
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0
    error_message = "log_delivery alone must not enable versioning"
  }
}

run "expiration_prefix_applies_to_expire_rule" {
  command = plan

  variables {
    expiration_prefix = "tmp/"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).filter).prefix == "tmp/"
    error_message = "The expiration rule must be scoped to the prefix"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "Expiration days must not change when a prefix is set"
  }
}

run "expiration_prefix_with_versioning_keeps_both_rules" {
  command = plan

  variables {
    versioning        = {}
    expiration_prefix = "tmp/"
  }

  assert {
    condition     = one(one([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "expire-objects"]).filter).prefix == "tmp/"
    error_message = "The expire rule must use the prefix"
  }

}

run "expiration_prefix_empty_rejected" {
  command = plan

  variables {
    expiration_prefix = ""
  }

  expect_failures = [var.expiration_prefix]
}

run "lambda_notification_created" {
  command = plan

  variables {
    lambda_notifications = {
      thumbnails = {
        function_arn  = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-thumbnails"
        filter_prefix = "uploads/"
        filter_suffix = ".jpg"
      }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 1
    error_message = "A non-empty lambda_notifications must create the notification"
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].lambda_function) == 1
    error_message = "One lambda_function block per entry"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : l.lambda_function_arn]) == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-thumbnails"
    error_message = "The function ARN must be passed through"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : toset(l.events)]) == toset(["s3:ObjectCreated:*"])
    error_message = "events must default to s3:ObjectCreated:*"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : l.filter_prefix]) == "uploads/"
    error_message = "filter_prefix must be applied"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : l.filter_suffix]) == ".jpg"
    error_message = "filter_suffix must be applied"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : l.id]) == "thumbnails"
    error_message = "The map key must be the notification id"
  }
}

run "lambda_notification_custom_events_without_filter" {
  command = plan

  variables {
    lambda_notifications = {
      cleanup = {
        function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-cleanup:live"
        events       = ["s3:ObjectRemoved:*", "s3:ObjectRestore:Completed"]
      }
    }
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : toset(l.events)]) == toset(["s3:ObjectRemoved:*", "s3:ObjectRestore:Completed"])
    error_message = "Custom events must be applied"
  }

  assert {
    condition     = one([for l in aws_s3_bucket_notification.this[0].lambda_function : l.filter_prefix]) == null
    error_message = "No filter_prefix when none is given"
  }
}

run "lambda_notification_multiple_entries" {
  command = plan

  variables {
    lambda_notifications = {
      a = { function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-a" }
      b = { function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-b" }
    }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this[0].lambda_function) == 2
    error_message = "Two entries must produce two lambda_function blocks"
  }
}

run "lambda_notification_non_lambda_arn_rejected" {
  command = plan

  variables {
    lambda_notifications = {
      bad = { function_arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-queue" }
    }
  }

  expect_failures = [var.lambda_notifications]
}

run "lambda_notification_layer_arn_rejected" {
  command = plan

  variables {
    lambda_notifications = {
      bad = { function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:layer:alpha-dev-layer:1" }
    }
  }

  expect_failures = [var.lambda_notifications]
}

run "lambda_notification_empty_events_rejected" {
  command = plan

  variables {
    lambda_notifications = {
      bad = {
        function_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-a"
        events       = []
      }
    }
  }

  expect_failures = [var.lambda_notifications]
}
