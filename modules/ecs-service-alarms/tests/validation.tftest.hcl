mock_provider "aws" {}

variables {
  name         = "alpha-api"
  cluster_name = "alpha-dev"
  service_name = "alpha-api"
}

# sns_topic_arns has no default. terraform test cannot expect_failures on a missing required variable
# (it errors before validation), so that is checked by hand: dropping the variable fails with
# "No value for required variable".

run "sns_topic_empty" {
  command = plan
  variables {
    sns_topic_arns = []
  }
  expect_failures = [var.sns_topic_arns]
}

run "sns_arn_is_sqs" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:q"]
  }
  expect_failures = [var.sns_topic_arns]
}

run "sns_arn_passes" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 7
    error_message = "A valid SNS ARN must pass"
  }
}

run "alb_suffix_without_app_prefix" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    load_balancer  = { alb_arn_suffix = "alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }
  expect_failures = [var.load_balancer]
}

run "target_group_suffix_without_prefix" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    load_balancer  = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "alpha-api/def" }
  }
  expect_failures = [var.load_balancer]
}

run "full_arn_target_group_rejected" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    load_balancer  = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-api/def" }
  }
  expect_failures = [var.load_balancer]
}

run "correct_suffixes_pass" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    load_balancer  = { alb_arn_suffix = "app/alpha/abc", target_group_arn_suffix = "targetgroup/alpha-api/def" }
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 12
    error_message = "Correct suffixes must pass and add ALB alarms"
  }
}

run "name_uppercase" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    name           = "Alpha-api"
  }
  expect_failures = [var.name]
}

run "name_with_space" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    name           = "alpha api"
  }
  expect_failures = [var.name]
}
