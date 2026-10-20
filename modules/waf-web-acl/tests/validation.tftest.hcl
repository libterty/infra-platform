mock_provider "aws" {}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_wafv2_web_acl.this
  override_during = plan
  values = {
    arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev-waf/11111111-2222-3333-4444-555555555555"
  }
}

override_resource {
  target          = aws_wafv2_ip_set.allowlist
  override_during = plan
  values = {
    arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/ipset/alpha-dev-waf-allowlist/66666666-7777-8888-9999-000000000000"
  }
}

variables {
  name = "alpha-dev-waf"
}

run "name_of_128_chars_is_accepted" {
  command = plan

  variables {
    name = join("", [for i in range(128) : "a"])
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.name) == 128
    error_message = "128 chars is the WAF limit and must be accepted"
  }
}

run "name_of_129_chars_is_rejected" {
  command = plan

  variables {
    name = join("", [for i in range(129) : "a"])
  }

  expect_failures = [var.name]
}

run "empty_name_is_rejected" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "name_with_space_is_rejected" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "name_with_dot_is_rejected" {
  command = plan

  variables {
    name = "alpha.dev"
  }

  expect_failures = [var.name]
}

run "name_with_underscore_and_hyphen_is_accepted" {
  command = plan

  variables {
    name = "alpha_dev-waf"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "alpha_dev-waf"
    error_message = "Underscore and hyphen are valid in WAF names"
  }
}

run "all_features_together_are_accepted" {
  command = plan

  variables {
    kill_switch = { action = "block", response_json = "{\"message\":\"maintenance\"}" }
    rate_limit  = { limit = 2000, allowlist_cidrs = ["10.10.0.0/16"] }
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] },
    ]
    body_size_exempt_path_prefixes = ["/upload"]
    logging                        = { redacted_headers = ["authorization", "cookie", "X-Origin-Verify"] }
    tags                           = { Project = "alpha" }
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 4
    error_message = "kill switch, rate limit, one managed group and body size make 4 rules"
  }
}
