mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_resource {
  target          = aws_sns_topic.this
  override_during = plan
  values          = { arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms" }
}

variables {
  name = "alpha-dev-alarms"
}

run "no_publishers_create_no_topic_policy" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_policy.this) == 0
    error_message = "With service_publishers empty the topic must keep its default policy"
  }

  assert {
    condition     = length(data.aws_caller_identity.current) == 0
    error_message = "With service_publishers empty the module must not read the caller identity"
  }
}

run "three_services_get_publish_with_source_account" {
  command = plan

  variables {
    service_publishers = ["events.amazonaws.com", "budgets.amazonaws.com", "backup.amazonaws.com"]
  }

  assert {
    condition     = aws_sns_topic_policy.this[0].arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
    error_message = "The policy must be attached to this topic"
  }

  assert {
    condition     = [for s in jsondecode(aws_sns_topic_policy.this[0].policy).Statement : s.Sid] == ["OwnerAccountAccess", "AllowServicePublish"]
    error_message = "The policy must keep the owner statement and add one service statement"
  }

  assert {
    condition = jsondecode(aws_sns_topic_policy.this[0].policy).Statement[1] == {
      Sid       = "AllowServicePublish"
      Effect    = "Allow"
      Principal = { Service = ["backup.amazonaws.com", "budgets.amazonaws.com", "events.amazonaws.com"] }
      Action    = "sns:Publish"
      Resource  = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      Condition = { StringEquals = { "aws:SourceAccount" = "111111111111" } }
    }
    error_message = "Services may only sns:Publish to this topic on behalf of the current account"
  }
}

run "owner_statement_matches_sns_default" {
  command = plan

  variables {
    service_publishers = ["budgets.amazonaws.com"]
  }

  assert {
    condition = jsondecode(aws_sns_topic_policy.this[0].policy).Statement[0] == {
      Sid       = "OwnerAccountAccess"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action = [
        "SNS:AddPermission",
        "SNS:DeleteTopic",
        "SNS:GetTopicAttributes",
        "SNS:ListSubscriptionsByTopic",
        "SNS:Publish",
        "SNS:RemovePermission",
        "SNS:SetTopicAttributes",
        "SNS:Subscribe",
      ]
      Resource  = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      Condition = { StringEquals = { "AWS:SourceOwner" = "111111111111" } }
    }
    error_message = "The owner statement must reproduce the SNS default policy, limited to the current account"
  }
}

run "duplicate_publishers_collapse" {
  command = plan

  variables {
    service_publishers = ["events.amazonaws.com", "events.amazonaws.com"]
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this[0].policy).Statement[1].Principal.Service == ["events.amazonaws.com"]
    error_message = "A repeated principal must appear once"
  }
}

run "principal_without_amazonaws_suffix_rejected" {
  command = plan

  variables {
    service_publishers = ["events.example.com"]
  }

  expect_failures = [var.service_publishers]
}

run "account_principal_rejected" {
  command = plan

  variables {
    service_publishers = ["111111111111"]
  }

  expect_failures = [var.service_publishers]
}

run "wildcard_principal_rejected" {
  command = plan

  variables {
    service_publishers = ["*.amazonaws.com"]
  }

  expect_failures = [var.service_publishers]
}
