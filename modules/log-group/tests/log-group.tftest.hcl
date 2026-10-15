mock_provider "aws" {}

variables {
  name = "/alpha/dev/worker"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/alpha/dev/worker"
    error_message = "Log group name must equal the name input"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Default retention must be 30 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Without kms_key_arn the group must not set a key"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Name = "/alpha/dev/worker" })
    error_message = "Without tags input the only tag is Name"
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.this) == 0
    error_message = "subscription = null must create no subscription filter"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags == tomap({ Project = "alpha", Name = "/alpha/dev/worker" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "retention_override" {
  command = plan

  variables {
    retention_days = 365
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "retention_in_days must follow retention_days"
  }
}

run "kms_when_given" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_id must equal kms_key_arn"
  }
}

run "lambda_subscription_without_role" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:forwarder"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.this) == 1
    error_message = "A subscription must create exactly one filter"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this[0].filter_pattern == ""
    error_message = "filter_pattern must default to empty"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this[0].log_group_name == "/alpha/dev/worker"
    error_message = "The filter must attach to the log group"
  }
}

run "firehose_subscription_with_role" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/logs"
      filter_pattern  = "ERROR"
      role_arn        = "arn:aws:iam::111111111111:role/cwl-to-firehose"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this[0].role_arn == "arn:aws:iam::111111111111:role/cwl-to-firehose"
    error_message = "role_arn must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.this[0].filter_pattern == "ERROR"
    error_message = "filter_pattern must be passed through"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.name == "/alpha/dev/worker"
    error_message = "name output must equal the log group name"
  }

  assert {
    condition     = output.arn == aws_cloudwatch_log_group.this.arn
    error_message = "arn output must expose the log group ARN"
  }
}

run "retention_zero_rejected" {
  command = plan

  variables {
    retention_days = 0
  }

  expect_failures = [var.retention_days]
}

run "retention_two_rejected" {
  command = plan

  variables {
    retention_days = 2
  }

  expect_failures = [var.retention_days]
}

run "retention_min_passes" {
  command = plan

  variables {
    retention_days = 1
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 1
    error_message = "1 day is a valid retention"
  }
}

run "retention_max_passes" {
  command = plan

  variables {
    retention_days = 3653
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 3653
    error_message = "3653 days is a valid retention"
  }
}

run "name_aws_prefix_rejected" {
  command = plan

  variables {
    name = "aws/foo"
  }

  expect_failures = [var.name]
}

run "name_with_space_rejected" {
  command = plan

  variables {
    name = "my group"
  }

  expect_failures = [var.name]
}

run "name_aws_lookalike_passes" {
  command = plan

  variables {
    name = "/aws/lambda/foo"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/foo"
    error_message = "Only names starting with aws/ are reserved"
  }
}

run "s3_destination_rejected" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:s3:::my-bucket"
    }
  }

  expect_failures = [var.subscription]
}

run "kinesis_without_role_rejected" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/logs"
    }
  }

  expect_failures = [var.subscription]
}

run "firehose_without_role_rejected" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/logs"
    }
  }

  expect_failures = [var.subscription]
}

run "kinesis_with_role_passes" {
  command = plan

  variables {
    subscription = {
      destination_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/logs"
      role_arn        = "arn:aws:iam::111111111111:role/cwl-to-kinesis"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.this) == 1
    error_message = "Kinesis with role_arn must be accepted"
  }
}
