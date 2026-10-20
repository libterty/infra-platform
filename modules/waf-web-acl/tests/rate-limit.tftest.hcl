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

run "no_rate_limit_no_rule_no_ip_set" {
  command = plan

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit"]) == 0
    error_message = "rate_limit = null must create no rate-limit rule"
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowlist) == 0
    error_message = "rate_limit = null must create no IP set"
  }
}

run "rate_limit_without_allowlist" {
  command = plan

  variables {
    rate_limit = { limit = 2000 }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit" && r.statement[0].rate_based_statement[0].limit == 2000 && r.statement[0].rate_based_statement[0].aggregate_key_type == "IP" && length(r.action[0].block) == 1]) == 1
    error_message = "rate_limit must block per source IP above the limit"
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowlist) == 0
    error_message = "An empty allowlist must not create an IP set"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit" && length(r.statement[0].rate_based_statement[0].scope_down_statement) == 0]) == 1
    error_message = "Without an allowlist the rate rule has no scope-down"
  }

  assert {
    condition     = output.ip_set_arn == null
    error_message = "ip_set_arn must be null without an allowlist"
  }
}

run "explicit_empty_allowlist_creates_no_ip_set" {
  command = plan

  variables {
    rate_limit = { limit = 2000, allowlist_cidrs = [] }
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowlist) == 0
    error_message = "allowlist_cidrs = [] must not create an IP set"
  }
}

run "allowlist_creates_one_ip_set_referenced_by_the_rate_rule" {
  command = plan

  variables {
    rate_limit = { limit = 2000, allowlist_cidrs = ["10.10.0.0/16", "203.0.113.7/32"] }
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowlist) == 1
    error_message = "A non-empty allowlist must create exactly one IP set"
  }

  assert {
    condition     = aws_wafv2_ip_set.allowlist[0].scope == "REGIONAL" && aws_wafv2_ip_set.allowlist[0].ip_address_version == "IPV4" && aws_wafv2_ip_set.allowlist[0].name == "alpha-dev-waf-allowlist"
    error_message = "IP set must be REGIONAL, IPV4 and named <name>-allowlist"
  }

  assert {
    condition     = toset(aws_wafv2_ip_set.allowlist[0].addresses) == toset(["10.10.0.0/16", "203.0.113.7/32"])
    error_message = "IP set must hold the allowlist CIDRs"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit" && r.statement[0].rate_based_statement[0].scope_down_statement[0].not_statement[0].statement[0].ip_set_reference_statement[0].arn == aws_wafv2_ip_set.allowlist[0].arn]) == 1
    error_message = "The rate rule must skip requests from the IP set (NOT ip_set_reference)"
  }

  assert {
    condition     = output.ip_set_arn == "arn:aws:wafv2:ap-northeast-1:111111111111:regional/ipset/alpha-dev-waf-allowlist/66666666-7777-8888-9999-000000000000"
    error_message = "ip_set_arn must be the IP set ARN"
  }
}

# Negative: the allowlist only lifts the rate limit, it must never become an allow rule that skips the other rules.
run "allowlist_never_creates_an_allow_rule" {
  command = plan

  variables {
    rate_limit          = { limit = 2000, allowlist_cidrs = ["10.10.0.0/16"] }
    kill_switch         = { action = "count" }
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if length(r.action) > 0 && length(r.action[0].allow) > 0]) == 0
    error_message = "No rule may use the allow action: allowlisted IPs stay subject to the other rules"
  }
}

run "limit_10_is_accepted" {
  command = plan

  variables {
    rate_limit = { limit = 10 }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit" && r.statement[0].rate_based_statement[0].limit == 10]) == 1
    error_message = "10 is the AWS minimum and must be accepted"
  }
}

run "limit_9_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 9 }
  }

  expect_failures = [var.rate_limit]
}

run "limit_zero_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 0 }
  }

  expect_failures = [var.rate_limit]
}

run "limit_negative_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = -5 }
  }

  expect_failures = [var.rate_limit]
}

run "limit_above_2_billion_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 2000000001 }
  }

  expect_failures = [var.rate_limit]
}

run "limit_2_billion_is_accepted" {
  command = plan

  variables {
    rate_limit = { limit = 2000000000 }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "rate-limit"]) == 1
    error_message = "2,000,000,000 is the AWS maximum and must be accepted"
  }
}

run "cidr_prefix_out_of_range_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["10.10.0.0/33"] }
  }

  expect_failures = [var.rate_limit]
}

run "cidr_not_a_cidr_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["not-a-cidr"] }
  }

  expect_failures = [var.rate_limit]
}

run "plain_ip_without_prefix_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["203.0.113.7"] }
  }

  expect_failures = [var.rate_limit]
}

run "match_everything_cidr_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["0.0.0.0/0"] }
  }

  expect_failures = [var.rate_limit]
}

run "ipv6_cidr_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["2001:db8::/32"] }
  }

  expect_failures = [var.rate_limit]
}

run "one_bad_cidr_among_good_ones_is_rejected" {
  command = plan

  variables {
    rate_limit = { limit = 100, allowlist_cidrs = ["10.10.0.0/16", "10.10.0.0/40"] }
  }

  expect_failures = [var.rate_limit]
}
