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

run "no_exempt_paths_no_body_size_rule" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "body-size-limit"]) == 0
    error_message = "Without exempt paths the common rule set's own body limit is enough"
  }
}

run "exempt_paths_without_common_rule_set_are_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "exempt_paths_with_other_groups_only_are_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesKnownBadInputsRuleSet" }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "exempt_paths_with_common_rule_set_but_no_override_are_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "exempt_paths_with_other_override_only_are_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["CrossSiteScripting_BODY"] }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "exempt_paths_with_same_named_group_from_other_vendor_are_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", vendor = "Partner", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "exempt_paths_with_size_restrictions_counted_are_accepted" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload", "/api/import/"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "body-size-limit"]) == 1
    error_message = "Exempt paths plus the count override must create the body-size rule"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "body-size-limit" && length(r.action[0].block) == 1]) == 1
    error_message = "The body-size rule must block"
  }

  assert {
    condition = length([
      for r in aws_wafv2_web_acl.this.rule : r
      if r.name == "body-size-limit" && length([
        for s in r.statement[0].and_statement[0].statement : s
        if length(s.size_constraint_statement) > 0 &&
        s.size_constraint_statement[0].comparison_operator == "GT" &&
        s.size_constraint_statement[0].size == 8192 &&
        s.size_constraint_statement[0].field_to_match[0].body[0].oversize_handling == "MATCH"
      ]) == 1
    ]) == 1
    error_message = "The rule must match bodies larger than 8192 bytes (oversized bodies count as a match)"
  }

  assert {
    condition = [
      for r in aws_wafv2_web_acl.this.rule : toset([
        for s in r.statement[0].and_statement[0].statement : s.not_statement[0].statement[0].byte_match_statement[0].search_string
        if length(s.not_statement) > 0
      ])
      if r.name == "body-size-limit"
    ][0] == toset(["/upload", "/api/import/"])
    error_message = "Every exempt prefix must be excluded from the rule"
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule : alltrue([
        for s in r.statement[0].and_statement[0].statement : s.not_statement[0].statement[0].byte_match_statement[0].positional_constraint == "STARTS_WITH"
        if length(s.not_statement) > 0
      ])
      if r.name == "body-size-limit"
    ])
    error_message = "Exempt paths are prefixes (STARTS_WITH)"
  }
}

run "single_exempt_path_is_accepted" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "body-size-limit"]) == 1
    error_message = "A single exempt path is valid"
  }
}

run "prefix_without_leading_slash_is_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "root_prefix_is_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}

run "duplicate_prefix_is_rejected" {
  command = plan

  variables {
    body_size_exempt_path_prefixes = ["/upload", "/upload"]
    managed_rule_groups            = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] }]
  }

  expect_failures = [var.body_size_exempt_path_prefixes]
}
