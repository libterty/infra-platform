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

run "default_creates_only_the_web_acl" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.name == "alpha-dev-waf"
    error_message = "Web ACL name must equal name"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL"
    error_message = "Scope must be REGIONAL"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 0
    error_message = "With nothing enabled the web ACL must have no rules"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].allow) == 1 && length(aws_wafv2_web_acl.this.default_action[0].block) == 0
    error_message = "Default action must be allow"
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowlist) == 0
    error_message = "No allowlist means no IP set"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 0 && length(aws_cloudwatch_log_group.waf) == 0
    error_message = "logging = null must create no logging configuration and no log group"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.custom_response_body) == 0
    error_message = "No kill switch means no custom response body"
  }
}

run "web_acl_visibility_config" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.visibility_config[0].metric_name == "alpha-dev-waf" && aws_wafv2_web_acl.this.visibility_config[0].cloudwatch_metrics_enabled == true && aws_wafv2_web_acl.this.visibility_config[0].sampled_requests_enabled == true
    error_message = "Web ACL must publish metrics and sampled requests under its own name"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-waf" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "default_outputs" {
  command = plan

  assert {
    condition     = output.web_acl_arn == "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev-waf/11111111-2222-3333-4444-555555555555"
    error_message = "web_acl_arn output is wrong"
  }

  assert {
    condition     = output.web_acl_name == "alpha-dev-waf"
    error_message = "web_acl_name output is wrong"
  }

  assert {
    condition     = output.ip_set_arn == null
    error_message = "ip_set_arn must be null when no IP set is created"
  }

  assert {
    condition     = output.log_group_name == null
    error_message = "log_group_name must be null when logging is off"
  }
}
