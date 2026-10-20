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

run "no_managed_groups_no_rules" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 0
    error_message = "managed_rule_groups = [] must add no rules"
  }
}

run "one_group_with_defaults" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "AWS-AWSManagedRulesCommonRuleSet" && r.statement[0].managed_rule_group_statement[0].name == "AWSManagedRulesCommonRuleSet" && r.statement[0].managed_rule_group_statement[0].vendor_name == "AWS"]) == 1
    error_message = "vendor must default to AWS and the rule must reference the group"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if length(r.override_action) > 0 && length(r.override_action[0].none) == 1 && length(r.override_action[0].count) == 0]) == 1
    error_message = "A managed group must keep its own actions (override_action none)"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if length(r.statement[0].managed_rule_group_statement[0].rule_action_override) > 0]) == 0
    error_message = "No count_overrides means no rule_action_override"
  }
}

# Negative: no managed group may run wholesale in count mode.
run "managed_groups_never_use_count_override_action" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] },
      { name = "AWSManagedRulesKnownBadInputsRuleSet" },
    ]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if length(r.override_action) > 0 && length(r.override_action[0].count) > 0]) == 0
    error_message = "count_overrides must only affect single rules, never the whole group"
  }
}

run "count_overrides_become_rule_action_overrides" {
  command = plan

  variables {
    managed_rule_groups = [{
      name            = "AWSManagedRulesCommonRuleSet"
      count_overrides = ["SizeRestrictions_BODY", "CrossSiteScripting_BODY"]
    }]
  }

  assert {
    condition = [
      for r in aws_wafv2_web_acl.this.rule : toset([for o in r.statement[0].managed_rule_group_statement[0].rule_action_override : o.name if length(o.action_to_use[0].count) == 1])
      if r.name == "AWS-AWSManagedRulesCommonRuleSet"
    ][0] == toset(["SizeRestrictions_BODY", "CrossSiteScripting_BODY"])
    error_message = "Every count_overrides entry must become a count rule_action_override"
  }
}

run "custom_vendor_is_passed_through" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "BotControl", vendor = "Partner" }]
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "Partner-BotControl" && r.statement[0].managed_rule_group_statement[0].vendor_name == "Partner"]) == 1
    error_message = "A non-default vendor must be used and prefix the rule name"
  }
}

run "same_name_different_vendor_is_accepted" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "Shared" },
      { name = "Shared", vendor = "Partner" },
    ]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 2
    error_message = "Same group name from different vendors is two rules"
  }
}

run "duplicate_group_is_rejected" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet" },
      { name = "AWSManagedRulesCommonRuleSet" },
    ]
  }

  expect_failures = [var.managed_rule_groups]
}

run "group_name_with_space_is_rejected" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "bad name" }]
  }

  expect_failures = [var.managed_rule_groups]
}

run "empty_group_name_is_rejected" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "" }]
  }

  expect_failures = [var.managed_rule_groups]
}

run "empty_vendor_is_rejected" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet", vendor = "" }]
  }

  expect_failures = [var.managed_rule_groups]
}

run "duplicate_count_override_is_rejected" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY", "SizeRestrictions_BODY"] }]
  }

  expect_failures = [var.managed_rule_groups]
}
