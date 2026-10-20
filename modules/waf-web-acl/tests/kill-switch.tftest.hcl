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


run "no_kill_switch_no_rule" {
  command = plan

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch"]) == 0
    error_message = "kill_switch = null must create no kill-switch rule"
  }
}

run "count_action" {
  command = plan

  variables {
    kill_switch = { action = "count" }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch"]) == 1
    error_message = "kill_switch must create exactly one rule"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch" && length(r.action[0].count) == 1 && length(r.action[0].block) == 0]) == 1
    error_message = "action = count must only count"
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch" && r.statement[0].size_constraint_statement[0].comparison_operator == "GE" && r.statement[0].size_constraint_statement[0].size == 0 && length(r.statement[0].size_constraint_statement[0].field_to_match[0].uri_path) == 1]) == 1
    error_message = "Kill switch must match every request (URI path size >= 0)"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.custom_response_body) == 0
    error_message = "count must not define a custom response body"
  }
}

run "block_action_without_body" {
  command = plan

  variables {
    kill_switch = { action = "block" }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch" && length(r.action[0].block) == 1 && length(r.action[0].count) == 0]) == 1
    error_message = "action = block must block"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.custom_response_body) == 0
    error_message = "Without response_json there is no custom response body"
  }
}

run "block_action_with_json_body" {
  command = plan

  variables {
    kill_switch = { action = "block", response_json = "{\"message\":\"maintenance\"}" }
  }

  assert {
    condition     = length([for r in aws_wafv2_web_acl.this.rule : r if r.name == "kill-switch" && r.action[0].block[0].custom_response[0].response_code == 503 && r.action[0].block[0].custom_response[0].custom_response_body_key == "kill-switch"]) == 1
    error_message = "block with response_json must answer 503 with the kill-switch body"
  }

  assert {
    condition     = length([for b in aws_wafv2_web_acl.this.custom_response_body : b if b.key == "kill-switch" && b.content_type == "APPLICATION_JSON" && b.content == "{\"message\":\"maintenance\"}"]) == 1
    error_message = "The body must be the given JSON with content type APPLICATION_JSON"
  }
}

run "action_allow_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "allow" }
  }

  expect_failures = [var.kill_switch]
}

run "action_uppercase_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "BLOCK" }
  }

  expect_failures = [var.kill_switch]
}

run "empty_action_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "" }
  }

  expect_failures = [var.kill_switch]
}

run "response_json_with_count_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "count", response_json = "{\"message\":\"maintenance\"}" }
  }

  expect_failures = [var.kill_switch]
}

run "invalid_json_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "block", response_json = "not json" }
  }

  expect_failures = [var.kill_switch]
}

run "oversize_json_is_rejected" {
  command = plan

  variables {
    kill_switch = { action = "block", response_json = "{\"m\":\"${format("%10300s", "x")}\"}" }
  }

  expect_failures = [var.kill_switch]
}
