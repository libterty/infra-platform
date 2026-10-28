mock_provider "aws" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_wafv2_web_acl.this
  override_during = plan
  values = {
    arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/alpha-dev-cdn-waf/11111111-2222-3333-4444-555555555555"
  }
}

override_resource {
  target          = aws_wafv2_ip_set.allowlist
  override_during = plan
  values = {
    arn = "arn:aws:wafv2:us-east-1:111111111111:global/ipset/alpha-dev-cdn-waf-allowlist/66666666-7777-8888-9999-000000000000"
  }
}

override_resource {
  target          = aws_cloudwatch_log_group.waf
  override_during = plan
  values = {
    arn = "arn:aws:logs:us-east-1:111111111111:log-group:aws-waf-logs-alpha-dev-cdn-waf"
  }
}

variables {
  name = "alpha-dev-cdn-waf"

  rate_limit = {
    limit           = 2000
    allowlist_cidrs = ["10.10.0.0/16"]
  }

  logging = {}
}

run "default_scope_is_regional_in_the_provider_region" {
  command = plan

  assert {
    condition     = var.scope == "REGIONAL"
    error_message = "scope must default to REGIONAL"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL" && aws_wafv2_ip_set.allowlist[0].scope == "REGIONAL"
    error_message = "Default scope of the web ACL and IP set must stay REGIONAL"
  }

  assert {
    condition     = local.region == null
    error_message = "REGIONAL must leave region null so resources follow the provider region"
  }
}

run "cloudfront_scope_puts_everything_in_us_east_1" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && aws_wafv2_ip_set.allowlist[0].scope == "CLOUDFRONT"
    error_message = "CLOUDFRONT must set the scope of the web ACL and IP set"
  }

  assert {
    condition = alltrue([
      aws_wafv2_web_acl.this.region == "us-east-1",
      aws_wafv2_ip_set.allowlist[0].region == "us-east-1",
      aws_cloudwatch_log_group.waf[0].region == "us-east-1",
      aws_wafv2_web_acl_logging_configuration.this[0].region == "us-east-1",
    ])
    error_message = "CLOUDFRONT must put the IP set, web ACL, log group and logging configuration in us-east-1"
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].name == "aws-waf-logs-alpha-dev-cdn-waf"
    error_message = "Log group name must not change with scope"
  }

  assert {
    condition     = one(aws_wafv2_web_acl.this.rule).statement[0].rate_based_statement[0].scope_down_statement[0].not_statement[0].statement[0].ip_set_reference_statement[0].arn == aws_wafv2_ip_set.allowlist[0].arn
    error_message = "The rate rule must still reference the allowlist IP set"
  }
}

run "cloudfront_accepts_a_us_east_1_log_key" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
    logging = {
      kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "A us-east-1 key must encrypt the CLOUDFRONT log group"
  }
}

run "cloudfront_rejects_a_log_key_from_another_region" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
    logging = {
      kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  expect_failures = [var.logging]
}

run "lowercase_scope_is_rejected" {
  command = plan

  variables {
    scope = "cloudfront"
  }

  expect_failures = [var.scope]
}

run "unknown_scope_is_rejected" {
  command = plan

  variables {
    scope = "GLOBAL"
  }

  expect_failures = [var.scope]
}
