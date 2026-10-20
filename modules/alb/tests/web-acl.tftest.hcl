mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev/0123456789abcdef"
      arn_suffix = "app/alpha-dev/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/fedcba9876543210"
    }
  }
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
}

run "web_acl_with_unknown_arn_in_same_configuration" {
  command = plan

  module {
    source = "./tests/fixtures/same-config-waf"
  }

  assert {
    condition     = output.association_count == 1
    error_message = "A Web ACL created in the same configuration must be associated (count must not depend on the unknown ARN)"
  }
}

run "web_acl_object_creates_association" {
  command = plan

  variables {
    web_acl = { arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1 && aws_wafv2_web_acl_association.this[0].web_acl_arn == "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "web_acl must create one association using web_acl.arn"
  }
}

run "no_web_acl_no_association" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "Without web_acl and web_acl_arn there must be no association"
  }
}

run "known_web_acl_arn_still_works" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "web_acl_arn with a known value must keep working"
  }
}

run "rejects_web_acl_and_web_acl_arn_together" {
  command = plan

  variables {
    web_acl     = { arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
    web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  expect_failures = [var.web_acl]
}

run "rejects_web_acl_malformed_arn" {
  command = plan

  variables {
    web_acl = { arn = "not-an-arn" }
  }

  expect_failures = [var.web_acl]
}

run "rejects_web_acl_cloudfront_scope_arn" {
  command = plan

  variables {
    web_acl = { arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/alpha-dev/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  }

  expect_failures = [var.web_acl]
}
