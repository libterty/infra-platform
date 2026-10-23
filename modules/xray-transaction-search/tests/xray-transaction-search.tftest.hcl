mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      name   = "ap-northeast-1"
      region = "ap-northeast-1"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "111111111111"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

run "resource_policy_lets_xray_write_spans" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_resource_policy.xray.policy_name == "xray-transaction-search"
    error_message = "resource_policy_name must default to xray-transaction-search"
  }
  assert {
    condition = jsondecode(aws_cloudwatch_log_resource_policy.xray.policy_document).Statement == [{
      Sid       = "TransactionSearchXRayAccess"
      Effect    = "Allow"
      Principal = { Service = "xray.amazonaws.com" }
      Action    = "logs:PutLogEvents"
      Resource = [
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:aws/spans:*",
        "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/application-signals/data:*",
      ]
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:aws:xray:ap-northeast-1:111111111111:*" }
        StringEquals = { "aws:SourceAccount" = "111111111111" }
      }
    }]
    error_message = "Policy must match the AWS Transaction Search policy scoped to this account and region"
  }
}

run "destination_and_default_indexing" {
  command = plan

  assert {
    condition     = aws_xray_trace_segment_destination.this.destination == "CloudWatchLogs"
    error_message = "Spans must go to CloudWatchLogs"
  }
  assert {
    condition     = aws_xray_indexing_rule.default.name == "Default"
    error_message = "Only the Default indexing rule exists"
  }
  assert {
    condition     = aws_xray_indexing_rule.default.rule[0].probabilistic[0].desired_sampling_percentage == 1
    error_message = "indexing_percentage must default to 1, the free tier"
  }
  assert {
    condition     = output.spans_log_group_name == "aws/spans"
    error_message = "spans_log_group_name must be aws/spans"
  }
}

run "custom_inputs" {
  command = plan

  variables {
    indexing_percentage  = 5
    resource_policy_name = "alpha-xray-spans"
  }

  assert {
    condition     = aws_xray_indexing_rule.default.rule[0].probabilistic[0].desired_sampling_percentage == 5 && output.indexing_percentage == 5
    error_message = "indexing_percentage must follow the input"
  }
  assert {
    condition     = aws_cloudwatch_log_resource_policy.xray.policy_name == "alpha-xray-spans"
    error_message = "resource_policy_name must follow the input"
  }
}

run "rejects_negative_percentage" {
  command = plan

  variables {
    indexing_percentage = -1
  }

  expect_failures = [var.indexing_percentage]
}

run "rejects_percentage_over_100" {
  command = plan

  variables {
    indexing_percentage = 101
  }

  expect_failures = [var.indexing_percentage]
}

run "rejects_blank_policy_name" {
  command = plan

  variables {
    resource_policy_name = " "
  }

  expect_failures = [var.resource_policy_name]
}
