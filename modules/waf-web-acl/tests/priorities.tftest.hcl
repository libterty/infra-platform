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

run "priorities_follow_the_fixed_order" {
  command = plan

  variables {
    kill_switch = { action = "count" }
    rate_limit  = { limit = 2000, allowlist_cidrs = ["10.10.0.0/16"] }
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] },
      { name = "AWSManagedRulesKnownBadInputsRuleSet" },
      { name = "AWSManagedRulesSQLiRuleSet" },
    ]
    body_size_exempt_path_prefixes = ["/upload"]
  }

  assert {
    condition = { for r in aws_wafv2_web_acl.this.rule : r.name => r.priority } == {
      "kill-switch"                              = 10
      "rate-limit"                               = 30
      "AWS-AWSManagedRulesCommonRuleSet"         = 100
      "AWS-AWSManagedRulesKnownBadInputsRuleSet" = 101
      "AWS-AWSManagedRulesSQLiRuleSet"           = 102
      "body-size-limit"                          = 1000
    }
    error_message = "Priorities must be kill switch, rate limit, managed groups in list order, then body size"
  }

  assert {
    condition     = length(distinct([for r in aws_wafv2_web_acl.this.rule : r.priority])) == length(aws_wafv2_web_acl.this.rule)
    error_message = "Priorities must be unique"
  }
}

run "managed_groups_keep_list_order" {
  command = plan

  variables {
    managed_rule_groups = [
      { name = "ZetaGroup" },
      { name = "AlphaGroup" },
    ]
  }

  assert {
    condition     = { for r in aws_wafv2_web_acl.this.rule : r.name => r.priority } == { "AWS-ZetaGroup" = 100, "AWS-AlphaGroup" = 101 }
    error_message = "Managed groups must be ordered as listed, not sorted"
  }
}

run "priorities_do_not_shift_when_optional_rules_are_absent" {
  command = plan

  variables {
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = { for r in aws_wafv2_web_acl.this.rule : r.name => r.priority } == { "AWS-AWSManagedRulesCommonRuleSet" = 100 }
    error_message = "A managed group keeps its priority whether or not the earlier rules exist"
  }
}

run "kill_switch_is_evaluated_before_everything_else" {
  command = plan

  variables {
    kill_switch         = { action = "block" }
    rate_limit          = { limit = 100 }
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = min([for r in aws_wafv2_web_acl.this.rule : r.priority]...) == [for r in aws_wafv2_web_acl.this.rule : r.priority if r.name == "kill-switch"][0]
    error_message = "The kill switch must have the lowest priority number"
  }
}

run "rule_visibility_metrics_use_the_rule_name" {
  command = plan

  variables {
    kill_switch         = { action = "count" }
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].metric_name == r.name && r.visibility_config[0].cloudwatch_metrics_enabled == true && r.visibility_config[0].sampled_requests_enabled == true])
    error_message = "Every rule must publish metrics and sampled requests under its own name"
  }
}
