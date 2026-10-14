mock_provider "aws" {}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "name_too_long" {
  command = plan
  variables {
    name = format("%33s", "x")
  }
  expect_failures = [var.name]
}

run "name_leading_hyphen" {
  command = plan
  variables {
    name = "-alpha"
  }
  expect_failures = [var.name]
}

run "name_trailing_hyphen" {
  command = plan
  variables {
    name = "alpha-"
  }
  expect_failures = [var.name]
}

run "name_internal_prefix" {
  command = plan
  variables {
    name = "internal-alpha"
  }
  expect_failures = [var.name]
}

run "name_32_chars_passes" {
  command = plan
  variables {
    name = replace(format("%32s", ""), " ", "a")
  }
  assert {
    condition     = length(aws_lb.this.name) == 32
    error_message = "32 characters must pass"
  }
}

run "idle_timeout_zero" {
  command = plan
  variables {
    idle_timeout = 0
  }
  expect_failures = [var.idle_timeout]
}

run "idle_timeout_4001" {
  command = plan
  variables {
    idle_timeout = 4001
  }
  expect_failures = [var.idle_timeout]
}

run "idle_timeout_bounds_pass" {
  command = plan
  variables {
    idle_timeout = 1
  }
  assert {
    condition     = aws_lb.this.idle_timeout == 1
    error_message = "1 must pass"
  }
}

run "idle_timeout_upper_bound_passes" {
  command = plan
  variables {
    idle_timeout = 4000
  }
  assert {
    condition     = aws_lb.this.idle_timeout == 4000
    error_message = "4000 must pass"
  }
}

run "subnet_single" {
  command = plan
  variables {
    subnet_ids = ["subnet-aaa"]
  }
  expect_failures = [var.subnet_ids]
}

run "subnet_duplicates" {
  command = plan
  variables {
    subnet_ids = ["subnet-aaa", "subnet-aaa"]
  }
  expect_failures = [var.subnet_ids]
}

run "subnet_two_passes" {
  command = plan
  assert {
    condition     = length(aws_lb.this.subnets) == 2
    error_message = "Two subnets must pass"
  }
}

run "security_group_required" {
  command = plan
  variables {
    security_group_ids = []
  }
  expect_failures = [var.security_group_ids]
}

run "certificate_arn_not_acm" {
  command = plan
  variables {
    certificate_arn = "arn:aws:iam::111111111111:server-certificate/x"
  }
  expect_failures = [var.certificate_arn]
}

run "certificate_arn_acm_passes" {
  command = plan
  variables {
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/abc"
  }
  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "An ACM ARN must pass"
  }
}

run "web_acl_arn_not_regional_wafv2" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/x/abc"
  }
  expect_failures = [var.web_acl_arn]
}

run "sns_topic_required" {
  command = plan
  variables {
    sns_topic_arns = []
  }
  expect_failures = [var.sns_topic_arns]
}

run "sns_topic_not_sns_arn" {
  command = plan
  variables {
    sns_topic_arns = ["arn:aws:sqs:ap-northeast-1:111111111111:q"]
  }
  expect_failures = [var.sns_topic_arns]
}
