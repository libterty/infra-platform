mock_provider "aws" {}

variables {
  name           = "alpha-dev-trail"
  s3_bucket_name = "alpha-dev-audit-logs"
  kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "single_account_multi_region_with_cloudwatch_logs" {
  command = plan

  variables {
    s3_key_prefix = "cloudtrail"
    cloudwatch_logs = {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/alpha-dev:*"
      role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-cloudtrail-logs"
    }
  }

  assert {
    condition     = aws_cloudtrail.this.name == "alpha-dev-trail" && aws_cloudtrail.this.s3_bucket_name == "alpha-dev-audit-logs" && aws_cloudtrail.this.s3_key_prefix == "cloudtrail"
    error_message = "Name, bucket and prefix must be passed through"
  }

  assert {
    condition     = aws_cloudtrail.this.is_multi_region_trail == true && aws_cloudtrail.this.is_organization_trail == false
    error_message = "The trail must be multi-region and not an organization trail by default"
  }

  assert {
    condition     = aws_cloudtrail.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The trail must be encrypted with the given CMK"
  }

  assert {
    condition     = aws_cloudtrail.this.enable_log_file_validation == true
    error_message = "Log file validation must always be on"
  }

  assert {
    condition     = aws_cloudtrail.this.include_global_service_events == true && aws_cloudtrail.this.enable_logging == true
    error_message = "Global service events and logging must always be on"
  }

  assert {
    condition     = aws_cloudtrail.this.cloud_watch_logs_group_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/alpha-dev:*" && aws_cloudtrail.this.cloud_watch_logs_role_arn == "arn:aws:iam::111111111111:role/alpha-dev-cloudtrail-logs"
    error_message = "CloudWatch Logs delivery must use the given log group and role"
  }

  assert {
    condition     = aws_cloudtrail.this.tags["Name"] == "alpha-dev-trail"
    error_message = "The Name tag must be the trail name"
  }
}

run "management_events_only_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.this.advanced_event_selector) == 0 && length(aws_cloudtrail.this.event_selector) == 0
    error_message = "Without selectors the trail records management events only"
  }

  assert {
    condition     = length(aws_cloudtrail.this.insight_selector) == 0
    error_message = "Insights must be off by default"
  }

  assert {
    condition     = aws_cloudtrail.this.cloud_watch_logs_group_arn == null && aws_cloudtrail.this.cloud_watch_logs_role_arn == null
    error_message = "No CloudWatch Logs delivery without cloudwatch_logs"
  }
}

run "organization_trail" {
  command = plan

  variables {
    is_organization_trail = true
    region                = "us-east-1"
  }

  assert {
    condition     = aws_cloudtrail.this.is_organization_trail == true && aws_cloudtrail.this.is_multi_region_trail == true
    error_message = "The organization trail must be multi-region"
  }

  assert {
    condition     = aws_cloudtrail.this.region == "us-east-1"
    error_message = "region must be set on the trail"
  }
}

run "data_events_and_insights" {
  command = plan

  variables {
    advanced_event_selectors = [
      {
        name = "management"
        field_selectors = [
          { field = "eventCategory", equals = ["Management"] },
        ]
      },
      {
        name = "s3-writes"
        field_selectors = [
          { field = "eventCategory", equals = ["Data"] },
          { field = "resources.type", equals = ["AWS::S3::Object"] },
          { field = "readOnly", equals = ["false"] },
        ]
      },
    ]
    insight_types = ["ApiCallRateInsight", "ApiErrorRateInsight"]
  }

  assert {
    condition     = length(aws_cloudtrail.this.advanced_event_selector) == 2 && aws_cloudtrail.this.advanced_event_selector[1].name == "s3-writes"
    error_message = "Advanced event selectors must be passed through in order"
  }

  assert {
    condition     = length(aws_cloudtrail.this.advanced_event_selector[1].field_selector) == 3
    error_message = "Field selectors must be passed through"
  }

  assert {
    condition     = toset([for s in aws_cloudtrail.this.insight_selector : s.insight_type]) == toset(["ApiCallRateInsight", "ApiErrorRateInsight"])
    error_message = "Insight types must be passed through"
  }
}

run "outputs" {
  command = apply

  override_resource {
    target = aws_cloudtrail.this
    values = {
      arn         = "arn:aws:cloudtrail:ap-northeast-1:111111111111:trail/alpha-dev-trail"
      home_region = "ap-northeast-1"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:cloudtrail:ap-northeast-1:111111111111:trail/alpha-dev-trail" && output.name == "alpha-dev-trail" && output.home_region == "ap-northeast-1"
    error_message = "Outputs must expose the trail ARN, name and home region"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "kms_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/audit"
  }

  expect_failures = [var.kms_key_arn]
}

run "organization_trail_must_be_multi_region" {
  command = plan

  variables {
    is_organization_trail = true
    is_multi_region_trail = false
  }

  expect_failures = [var.is_organization_trail]
}

run "log_group_arn_without_stream_wildcard_rejected" {
  command = plan

  variables {
    cloudwatch_logs = {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/alpha-dev"
      role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-cloudtrail-logs"
    }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "cloudwatch_logs_role_must_be_a_role_arn" {
  command = plan

  variables {
    cloudwatch_logs = {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/alpha-dev:*"
      role_arn      = "arn:aws:iam::111111111111:user/alpha"
    }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "invalid_trail_name_rejected" {
  command = plan

  variables {
    name = "alpha--trail"
  }

  expect_failures = [var.name]
}

run "unknown_insight_type_rejected" {
  command = plan

  variables {
    insight_types = ["ApiLatencyInsight"]
  }

  expect_failures = [var.insight_types]
}

run "empty_advanced_event_selectors_rejected" {
  command = plan

  variables {
    advanced_event_selectors = []
  }

  expect_failures = [var.advanced_event_selectors]
}

run "selector_without_event_category_rejected" {
  command = plan

  variables {
    advanced_event_selectors = [{
      name            = "s3"
      field_selectors = [{ field = "resources.type", equals = ["AWS::S3::Object"] }]
    }]
  }

  expect_failures = [var.advanced_event_selectors]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "us_east_1"
  }

  expect_failures = [var.region]
}
