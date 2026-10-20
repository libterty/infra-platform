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

override_resource {
  target          = aws_cloudwatch_log_group.waf
  override_during = plan
  values = {
    arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:aws-waf-logs-alpha-dev-waf"
  }
}

variables {
  name = "alpha-dev-waf"
}

run "no_logging_no_resources" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.waf) == 0 && length(aws_wafv2_web_acl_logging_configuration.this) == 0
    error_message = "logging = null must create nothing"
  }
}

run "logging_with_defaults" {
  command = plan

  variables {
    logging = {}
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].name == "aws-waf-logs-alpha-dev-waf"
    error_message = "Log group name must be aws-waf-logs-<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].retention_in_days == 14
    error_message = "Default retention must be 14 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].kms_key_id == null
    error_message = "Without kms_key_arn the group must not set a key"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 1
    error_message = "Logging must create one logging configuration"
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this[0].resource_arn == aws_wafv2_web_acl.this.arn
    error_message = "Logging must attach to the web ACL"
  }

  assert {
    condition     = toset(aws_wafv2_web_acl_logging_configuration.this[0].log_destination_configs) == toset([aws_cloudwatch_log_group.waf[0].arn])
    error_message = "Logging must deliver to the module log group"
  }

  assert {
    condition     = toset([for f in aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie"])
    error_message = "authorization and cookie must be redacted by default"
  }

  assert {
    condition     = output.log_group_name == "aws-waf-logs-alpha-dev-waf"
    error_message = "log_group_name output must be the log group name"
  }
}

run "custom_header_is_added_in_lowercase" {
  command = plan

  variables {
    logging = { redacted_headers = ["Authorization", "Cookie", "X-Origin-Verify"] }
  }

  assert {
    condition     = toset([for f in aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie", "x-origin-verify"])
    error_message = "Redacted header names must be lowercased and include the custom one"
  }
}

# Negative: authorization and cookie can never be dropped from the redaction list.
run "authorization_and_cookie_are_always_redacted" {
  command = plan

  variables {
    logging = { redacted_headers = ["x-origin-verify"] }
  }

  assert {
    condition     = toset([for f in aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie", "x-origin-verify"])
    error_message = "authorization and cookie must stay redacted even when the list omits them"
  }
}

run "empty_redacted_headers_still_redacts_defaults" {
  command = plan

  variables {
    logging = { redacted_headers = [] }
  }

  assert {
    condition     = toset([for f in aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie"])
    error_message = "An empty list must not turn redaction off"
  }
}

run "headers_differing_only_in_case_are_deduplicated" {
  command = plan

  variables {
    logging = { redacted_headers = ["Cookie", "COOKIE", "X-Origin-Verify"] }
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields) == 3
    error_message = "Case variants of the same header must collapse into one redacted field"
  }
}

run "retention_and_kms_override" {
  command = plan

  variables {
    logging = {
      retention_days = 90
      kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].retention_in_days == 90
    error_message = "retention_days must pass through"
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_arn must encrypt the log group"
  }
}

run "log_group_tags" {
  command = plan

  variables {
    logging = {}
    tags    = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].tags == tomap({ Project = "alpha", Name = "aws-waf-logs-alpha-dev-waf" })
    error_message = "Log group tags must be the input tags plus Name"
  }
}

run "retention_zero_is_rejected" {
  command = plan

  variables {
    logging = { retention_days = 0 }
  }

  expect_failures = [var.logging]
}

run "retention_unsupported_value_is_rejected" {
  command = plan

  variables {
    logging = { retention_days = 10 }
  }

  expect_failures = [var.logging]
}

run "header_with_space_is_rejected" {
  command = plan

  variables {
    logging = { redacted_headers = ["bad header"] }
  }

  expect_failures = [var.logging]
}

run "empty_header_name_is_rejected" {
  command = plan

  variables {
    logging = { redacted_headers = [""] }
  }

  expect_failures = [var.logging]
}

run "header_name_over_64_chars_is_rejected" {
  command = plan

  variables {
    logging = { redacted_headers = [join("", [for i in range(65) : "a"])] }
  }

  expect_failures = [var.logging]
}
