mock_provider "aws" {}

variables {
  name                = "alpha-dev-alarms"
  email_subscriptions = ["ops@example.com", "oncall@example.com"]
}

run "creates_one_topic_with_name" {
  command = plan

  assert {
    condition     = aws_sns_topic.this.name == "alpha-dev-alarms"
    error_message = "Topic name must equal the name input"
  }

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == null
    error_message = "Without kms_master_key_id the topic must not set a key"
  }

  assert {
    condition     = aws_sns_topic.this.tags == tomap({ Name = "alpha-dev-alarms" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_sns_topic.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-alarms" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "email_subscriptions_per_address" {
  command = plan

  assert {
    condition     = toset(keys(aws_sns_topic_subscription.email)) == toset(["ops@example.com", "oncall@example.com"])
    error_message = "One subscription per address, keyed by the address itself"
  }

  assert {
    condition     = alltrue([for k, s in aws_sns_topic_subscription.email : s.protocol == "email" && s.endpoint == k])
    error_message = "Every subscription must use protocol email and the address as endpoint"
  }
}

run "duplicate_addresses_collapse" {
  command = plan

  variables {
    email_subscriptions = ["ops@example.com", "ops@example.com"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "A repeated address must produce one subscription"
  }
}

run "no_subscribers_is_allowed" {
  command = plan

  variables {
    email_subscriptions = []
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "An empty email list must create no subscription"
  }

  assert {
    condition     = aws_sns_topic.this.name == "alpha-dev-alarms"
    error_message = "The topic must still be created without subscribers"
  }

  assert {
    condition     = length(output.subscription_arns) == 0
    error_message = "subscription_arns must be empty without subscribers"
  }
}

run "kms_key_is_applied" {
  command = plan

  variables {
    kms_master_key_id = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "The topic must use the given customer managed key"
  }
}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
run "outputs_expose_topic_and_subscriptions" {
  command = plan

  variables {
    email_subscriptions = ["ops@example.com"]
  }

  override_resource {
    target          = aws_sns_topic.this
    override_during = plan
    values          = { arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms" }
  }

  override_resource {
    target          = aws_sns_topic_subscription.email["ops@example.com"]
    override_during = plan
    values          = { arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms:sub-1" }
  }

  assert {
    condition     = output.topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
    error_message = "topic_arn must expose the topic ARN"
  }

  assert {
    condition     = output.topic_name == "alpha-dev-alarms"
    error_message = "topic_name must expose the topic name"
  }

  assert {
    condition     = output.subscription_arns == { "ops@example.com" = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms:sub-1" }
    error_message = "subscription_arns must be keyed by email address"
  }
}

run "email_format_accepts_valid_address" {
  command = plan

  variables {
    email_subscriptions = ["ops@example.com"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "A valid address must plan normally"
  }
}

run "email_format_rejects_missing_at" {
  command = plan

  variables {
    email_subscriptions = ["not-an-email"]
  }

  expect_failures = [var.email_subscriptions]
}

run "email_format_rejects_whitespace" {
  command = plan

  variables {
    email_subscriptions = ["ops @example.com"]
  }

  expect_failures = [var.email_subscriptions]
}

run "email_format_rejects_one_bad_entry_among_good" {
  command = plan

  variables {
    email_subscriptions = ["ops@example.com", "broken"]
  }

  expect_failures = [var.email_subscriptions]
}

run "rejects_aws_managed_sns_key" {
  command = plan

  variables {
    kms_master_key_id = "alias/aws/sns"
  }

  expect_failures = [var.kms_master_key_id]
}

run "accepts_customer_managed_alias" {
  command = plan

  variables {
    kms_master_key_id = "alias/alarms"
  }

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == "alias/alarms"
    error_message = "A customer managed key alias must be accepted"
  }
}

run "topic_name_accepts_mixed_case_and_underscore" {
  command = plan

  variables {
    name = "Alpha_Dev-Alarms"
  }

  assert {
    condition     = aws_sns_topic.this.name == "Alpha_Dev-Alarms"
    error_message = "Upper case, underscore and hyphen are valid in a topic name"
  }
}

run "topic_name_accepts_256_chars" {
  command = plan

  variables {
    name = join("", [for i in range(256) : "a"])
  }

  assert {
    condition     = length(aws_sns_topic.this.name) == 256
    error_message = "256 characters is the allowed upper bound"
  }
}

run "topic_name_rejects_257_chars" {
  command = plan

  variables {
    name = join("", [for i in range(257) : "a"])
  }

  expect_failures = [var.name]
}

run "topic_name_rejects_space" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "topic_name_rejects_empty" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}
