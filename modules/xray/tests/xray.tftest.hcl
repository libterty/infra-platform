mock_provider "aws" {}

variables {
  name_prefix = "alpha-dev"
  sampling_rules = {
    health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" }
    api    = { priority = 200, fixed_rate = 0.05, service_name = "alpha-dev-api", attributes = { env = "dev" } }
  }
  groups = {
    errors = { filter_expression = "fault = true OR error = true" }
    slow   = { filter_expression = "responsetime > 3", insights_enabled = true, notifications_enabled = true }
  }
}

run "one_rule_per_entry" {
  command = plan

  assert {
    condition     = length(aws_xray_sampling_rule.this) == 2
    error_message = "Expected one sampling rule per entry"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["health"].rule_name == "alpha-dev-health" && aws_xray_sampling_rule.this["api"].rule_name == "alpha-dev-api"
    error_message = "rule_name must be <name_prefix>-<key>"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["health"].priority == 100 && aws_xray_sampling_rule.this["api"].priority == 200
    error_message = "priority must follow the input"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["health"].fixed_rate == 0 && aws_xray_sampling_rule.this["api"].fixed_rate == 0.05
    error_message = "fixed_rate must follow the input"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["health"].reservoir_size == 0 && aws_xray_sampling_rule.this["api"].reservoir_size == 1
    error_message = "reservoir_size must follow the input and default to 1"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["api"].attributes == tomap({ env = "dev" }) && length(coalesce(aws_xray_sampling_rule.this["health"].attributes, {})) == 0
    error_message = "attributes must follow the input"
  }
}

run "rule_wildcard_defaults" {
  command = plan

  assert {
    condition = (
      aws_xray_sampling_rule.this["health"].service_name == "*" &&
      aws_xray_sampling_rule.this["health"].service_type == "*" &&
      aws_xray_sampling_rule.this["health"].host == "*" &&
      aws_xray_sampling_rule.this["health"].http_method == "*" &&
      aws_xray_sampling_rule.this["health"].resource_arn == "*" &&
      aws_xray_sampling_rule.this["health"].version == 1
    )
    error_message = "Unset match fields must be * and version must be 1"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["health"].url_path == "/health" && aws_xray_sampling_rule.this["api"].url_path == "*"
    error_message = "url_path must follow the input and default to *"
  }
  assert {
    condition     = aws_xray_sampling_rule.this["api"].service_name == "alpha-dev-api"
    error_message = "service_name must follow the input"
  }
}

run "tags_reach_rules_and_groups" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_xray_sampling_rule.this["api"].tags == tomap({ Project = "alpha" }) && aws_xray_group.this["slow"].tags == tomap({ Project = "alpha" })
    error_message = "tags must be applied to rules and groups"
  }
}

run "one_group_per_entry" {
  command = plan

  assert {
    condition     = length(aws_xray_group.this) == 2
    error_message = "Expected one group per entry"
  }
  assert {
    condition     = aws_xray_group.this["errors"].group_name == "alpha-dev-errors" && aws_xray_group.this["slow"].group_name == "alpha-dev-slow"
    error_message = "group_name must be <name_prefix>-<key>"
  }
  assert {
    condition     = aws_xray_group.this["errors"].filter_expression == "fault = true OR error = true" && aws_xray_group.this["slow"].filter_expression == "responsetime > 3"
    error_message = "filter_expression must follow the input"
  }
  assert {
    condition = (
      aws_xray_group.this["errors"].insights_configuration[0].insights_enabled == false &&
      aws_xray_group.this["errors"].insights_configuration[0].notifications_enabled == false &&
      aws_xray_group.this["slow"].insights_configuration[0].insights_enabled == true &&
      aws_xray_group.this["slow"].insights_configuration[0].notifications_enabled == true
    )
    error_message = "insights_configuration must follow the input and default to false"
  }
}

run "empty_inputs_create_nothing" {
  command = plan

  variables {
    sampling_rules = {}
    groups         = {}
  }

  assert {
    condition     = length(aws_xray_sampling_rule.this) == 0 && length(aws_xray_group.this) == 0
    error_message = "Empty maps must create nothing"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_xray_sampling_rule.this["health"]
    override_during = plan
    values          = { arn = "arn:aws:xray:ap-northeast-1:111111111111:sampling-rule/alpha-dev-health" }
  }
  override_resource {
    target          = aws_xray_sampling_rule.this["api"]
    override_during = plan
    values          = { arn = "arn:aws:xray:ap-northeast-1:111111111111:sampling-rule/alpha-dev-api" }
  }
  override_resource {
    target          = aws_xray_group.this["errors"]
    override_during = plan
    values          = { arn = "arn:aws:xray:ap-northeast-1:111111111111:group/alpha-dev-errors/ABC" }
  }
  override_resource {
    target          = aws_xray_group.this["slow"]
    override_during = plan
    values          = { arn = "arn:aws:xray:ap-northeast-1:111111111111:group/alpha-dev-slow/DEF" }
  }

  assert {
    condition     = toset(keys(output.sampling_rule_arns)) == toset(["health", "api"])
    error_message = "sampling_rule_arns keys must equal the sampling_rules keys"
  }
  assert {
    condition     = toset(keys(output.group_arns)) == toset(["errors", "slow"])
    error_message = "group_arns keys must equal the groups keys"
  }
  assert {
    condition     = output.sampling_rule_arns["api"] == "arn:aws:xray:ap-northeast-1:111111111111:sampling-rule/alpha-dev-api" && output.group_arns["slow"] == "arn:aws:xray:ap-northeast-1:111111111111:group/alpha-dev-slow/DEF"
    error_message = "Outputs must expose the resource ARNs"
  }
}

run "rule_name_length_limit" {
  command = plan

  variables {
    name_prefix    = "abcdefghijklmnopqrstuvwxyz"                 # 26 chars
    sampling_rules = { abcde = { priority = 1, fixed_rate = 1 } } # 26 + 1 + 5 = 32
    groups         = {}
  }

  assert {
    condition     = length(aws_xray_sampling_rule.this) == 1
    error_message = "A 32 char rule name must pass"
  }
}

run "rule_name_too_long" {
  command = plan

  variables {
    name_prefix    = "abcdefghijklmnopqrstuvwxyz"
    sampling_rules = { abcdef = { priority = 1, fixed_rate = 1 } } # 33
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "group_name_exactly_32" {
  command = plan

  variables {
    name_prefix    = "abcdefghijklmnopqrstuvwxyz"
    sampling_rules = {}
    groups         = { abcde = { filter_expression = "fault = true" } }
  }

  assert {
    condition     = length(aws_xray_group.this) == 1
    error_message = "A 32 char group name must pass"
  }
}

run "group_name_too_long" {
  command = plan

  variables {
    name_prefix    = "abcdefghijklmnopqrstuvwxyz"
    sampling_rules = {}
    groups         = { abcdef = { filter_expression = "fault = true" } }
  }

  expect_failures = [var.groups]
}

run "priority_lower_bound_rejected" {
  command = plan

  variables {
    sampling_rules = { a = { priority = 0, fixed_rate = 1 } }
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "priority_upper_bound_rejected" {
  command = plan

  variables {
    sampling_rules = { a = { priority = 10000, fixed_rate = 1 } }
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "priority_edges_accepted" {
  command = plan

  variables {
    sampling_rules = {
      a = { priority = 1, fixed_rate = 1 }
      b = { priority = 9999, fixed_rate = 1 }
    }
    groups = {}
  }

  assert {
    condition     = length(aws_xray_sampling_rule.this) == 2
    error_message = "priority 1 and 9999 must pass"
  }
}

run "fixed_rate_too_high_rejected" {
  command = plan

  variables {
    sampling_rules = { a = { priority = 1, fixed_rate = 1.5 } }
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "fixed_rate_negative_rejected" {
  command = plan

  variables {
    sampling_rules = { a = { priority = 1, fixed_rate = -0.1 } }
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "fixed_rate_edges_accepted" {
  command = plan

  variables {
    sampling_rules = {
      a = { priority = 1, fixed_rate = 0 }
      b = { priority = 2, fixed_rate = 1 }
    }
    groups = {}
  }

  assert {
    condition     = length(aws_xray_sampling_rule.this) == 2
    error_message = "fixed_rate 0 and 1 must pass"
  }
}

run "negative_reservoir_rejected" {
  command = plan

  variables {
    sampling_rules = { a = { priority = 1, fixed_rate = 1, reservoir_size = -1 } }
    groups         = {}
  }

  expect_failures = [var.sampling_rules]
}

run "duplicate_priority_rejected" {
  command = plan

  variables {
    sampling_rules = {
      a = { priority = 100, fixed_rate = 1 }
      b = { priority = 100, fixed_rate = 0 }
    }
    groups = {}
  }

  expect_failures = [var.sampling_rules]
}

run "empty_filter_rejected" {
  command = plan

  variables {
    sampling_rules = {}
    groups         = { a = { filter_expression = "" } }
  }

  expect_failures = [var.groups]
}

run "blank_filter_rejected" {
  command = plan

  variables {
    sampling_rules = {}
    groups         = { a = { filter_expression = "   " } }
  }

  expect_failures = [var.groups]
}

run "notifications_without_insights_rejected" {
  command = plan

  variables {
    sampling_rules = {}
    groups         = { a = { filter_expression = "fault = true", notifications_enabled = true, insights_enabled = false } }
  }

  expect_failures = [var.groups]
}

run "insights_without_notifications_accepted" {
  command = plan

  variables {
    sampling_rules = {}
    groups         = { a = { filter_expression = "fault = true", insights_enabled = true } }
  }

  assert {
    condition     = length(aws_xray_group.this) == 1
    error_message = "insights without notifications must pass"
  }
}
