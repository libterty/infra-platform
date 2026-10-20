mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev/0123456789abcdef"
      arn_suffix = "app/alpha-dev/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/fedcba9876543210"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef"
      arn_suffix = "targetgroup/alpha-dev-web/0123456789abcdef"
    }
  }
}

variables {
  name               = "alpha-dev"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-aaa"]
  sns_topic_arns     = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
  vpc_id             = "vpc-0123456789abcdef0"
  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
}

run "defaults_create_no_target_group_and_no_rule" {
  command = apply

  variables {
    vpc_id        = null
    target_groups = {}
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0
    error_message = "No target group or rule without target_groups and listener_rules"
  }

  assert {
    condition     = length(output.target_group_arns) == 0 && length(output.target_group_arn_suffixes) == 0
    error_message = "Target group outputs must be empty maps"
  }
}

run "target_groups_use_defaults" {
  command = plan

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "One target group per entry"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].name == "alpha-dev-web" && aws_lb_target_group.this["api"].name == "alpha-dev-api"
    error_message = "Target group name must be <name>-<key>"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].port == 8080 && aws_lb_target_group.this["web"].protocol == "HTTP" && aws_lb_target_group.this["web"].target_type == "ip" && aws_lb_target_group.this["web"].vpc_id == "vpc-0123456789abcdef0"
    error_message = "Port, protocol, target type and VPC must be set"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].protocol_version == "HTTP1" && aws_lb_target_group.this["web"].deregistration_delay == "300"
    error_message = "protocol_version must default to HTTP1 and deregistration_delay to 300"
  }

  assert {
    condition = (
      one(aws_lb_target_group.this["web"].health_check).path == "/health" &&
      one(aws_lb_target_group.this["web"].health_check).matcher == "200" &&
      one(aws_lb_target_group.this["web"].health_check).interval == 15 &&
      one(aws_lb_target_group.this["web"].health_check).timeout == 5 &&
      one(aws_lb_target_group.this["web"].health_check).healthy_threshold == 2 &&
      one(aws_lb_target_group.this["web"].health_check).unhealthy_threshold == 3
    )
    error_message = "Health check defaults must be /health, 200, 15, 5, 2, 3"
  }

  assert {
    condition     = aws_lb_target_group.this["web"].tags["Name"] == "alpha-dev-web"
    error_message = "Target group must carry the Name tag"
  }
}

run "target_group_overrides" {
  command = plan

  variables {
    target_groups = {
      grpc = {
        port                 = 50051
        protocol_version     = "GRPC"
        deregistration_delay = 30
        health_check = {
          path    = "/grpc.health.v1.Health/Check"
          matcher = "0"
        }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["grpc"].protocol_version == "GRPC" && aws_lb_target_group.this["grpc"].deregistration_delay == "30"
    error_message = "protocol_version and deregistration_delay must be overridable"
  }

  assert {
    condition     = one(aws_lb_target_group.this["grpc"].health_check).path == "/grpc.health.v1.Health/Check" && one(aws_lb_target_group.this["grpc"].health_check).matcher == "0" && one(aws_lb_target_group.this["grpc"].health_check).interval == 15
    error_message = "A partial health_check must override only the given fields"
  }
}

run "rules_attach_to_https_listener_with_certificate" {
  command = plan

  override_resource {
    target          = aws_lb_listener.https[0]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/https" }
  }

  override_resource {
    target          = aws_lb_listener.http
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/http" }
  }

  override_resource {
    target          = aws_lb_target_group.this["web"]
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/alpha-dev-web/0123456789abcdef" }
  }

  variables {
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/primary"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"], host_headers = ["www.example.com"], require_origin_verify = false }
      api = { priority = 20, target_group = "api", path_patterns = ["/api/*", "/v1/*"], require_origin_verify = false }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 2
    error_message = "One rule per entry"
  }

  assert {
    condition     = aws_lb_listener_rule.this["web"].listener_arn == aws_lb_listener.https[0].arn
    error_message = "With a certificate the rules must attach to the HTTPS listener"
  }

  assert {
    condition     = aws_lb_listener_rule.this["web"].priority == 10 && aws_lb_listener_rule.this["api"].priority == 20
    error_message = "Priority must pass through"
  }

  assert {
    condition     = one(aws_lb_listener_rule.this["web"].action).type == "forward" && one(aws_lb_listener_rule.this["web"].action).target_group_arn == aws_lb_target_group.this["web"].arn
    error_message = "The rule must forward to its target group"
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.this["web"].condition : one(c.path_pattern).values if length(c.path_pattern) > 0]) == toset(["/app/*"])
    error_message = "path_patterns must become a path_pattern condition"
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.this["web"].condition : one(c.host_header).values if length(c.host_header) > 0]) == toset(["www.example.com"])
    error_message = "host_headers must become a host_header condition"
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this["api"].condition : c if length(c.host_header) > 0]) == 0
    error_message = "No host_header condition when host_headers is empty"
  }
}

run "rules_attach_to_http_listener_without_certificate" {
  command = plan

  override_resource {
    target          = aws_lb_listener.http
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev/0123456789abcdef/http" }
  }

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"], require_origin_verify = false }
    }
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "No HTTPS listener without a certificate"
  }

  assert {
    condition     = aws_lb_listener_rule.this["web"].listener_arn == aws_lb_listener.http.arn
    error_message = "Without a certificate the rules must attach to the HTTP listener"
  }
}

run "origin_verify_adds_header_condition" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"], require_origin_verify = true }
    }
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this["web"].condition : c if length(c.http_header) > 0]) == 1
    error_message = "require_origin_verify = true must add one http_header condition"
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.this["web"].condition : one(c.http_header).http_header_name if length(c.http_header) > 0]) == "X-Origin-Verify"
    error_message = "The header condition must use the configured header name"
  }
}

run "origin_verify_defaults_to_off_even_when_header_is_configured" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"] }
    }
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this["web"].condition : c if length(c.http_header) > 0]) == 0
    error_message = "require_origin_verify must default to false: no header condition unless asked for"
  }
}

run "origin_verify_false_omits_header_condition" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"], require_origin_verify = false }
    }
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this["web"].condition : c if length(c.http_header) > 0]) == 0
    error_message = "require_origin_verify = false must not add a header condition"
  }
}

run "origin_verify_required_without_header_rejected" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"], require_origin_verify = true }
    }
  }

  expect_failures = [var.listener_rules]
}

run "origin_verify_not_required_without_header_accepted" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"] }
    }
  }

  assert {
    condition     = length([for c in aws_lb_listener_rule.this["web"].condition : c if length(c.http_header) > 0]) == 0
    error_message = "A rule that does not require the header needs no header configuration"
  }
}

run "outputs_map_target_groups" {
  command = apply

  assert {
    condition     = toset(keys(output.target_group_arns)) == toset(["web", "api"]) && toset(keys(output.target_group_arn_suffixes)) == toset(["web", "api"])
    error_message = "Target group outputs must be keyed by target_groups key"
  }

  assert {
    condition     = output.target_group_arns["web"] == aws_lb_target_group.this["web"].arn && output.target_group_arn_suffixes["web"] == aws_lb_target_group.this["web"].arn_suffix
    error_message = "Outputs must return the ARN and the ARN suffix"
  }
}

run "rule_to_unknown_target_group_rejected" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "missing", path_patterns = ["/app/*"] }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rule_to_existing_target_group_accepted" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "api", path_patterns = ["/app/*"] }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "A rule pointing to an existing target group must be accepted"
  }
}

run "duplicate_priority_rejected" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"] }
      api = { priority = 10, target_group = "api", path_patterns = ["/api/*"] }
    }
  }

  expect_failures = [var.listener_rules]
}

run "distinct_priorities_accepted" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/app/*"] }
      api = { priority = 11, target_group = "api", path_patterns = ["/api/*"] }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 2
    error_message = "Distinct priorities must be accepted"
  }
}

run "rule_without_condition_rejected" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web" }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rule_with_six_condition_values_rejected" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/1", "/2", "/3"], host_headers = ["a.example.com", "b.example.com", "c.example.com"] }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rule_with_five_condition_values_accepted" {
  command = plan

  variables {
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/1", "/2", "/3"], host_headers = ["a.example.com", "b.example.com"] }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "Five condition values must be accepted"
  }
}

run "origin_verify_header_counts_toward_condition_limit" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/1", "/2", "/3", "/4", "/5"], require_origin_verify = true }
    }
  }

  expect_failures = [var.listener_rules]
}

run "four_values_plus_origin_verify_header_accepted" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
    listener_rules = {
      web = { priority = 10, target_group = "web", path_patterns = ["/1", "/2", "/3", "/4"], require_origin_verify = true }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "Four values plus the origin verify header make five and must be accepted"
  }
}

run "target_group_name_over_32_rejected" {
  command = plan

  variables {
    target_groups = {
      "abcdefghijklmnopqrstuvw" = { port = 80 }
    }
  }

  expect_failures = [var.target_groups]
}

run "target_group_name_of_32_accepted" {
  command = plan

  variables {
    target_groups = {
      "abcdefghijklmnopqrstuv" = { port = 80 }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1
    error_message = "A 32 character target group name must be accepted"
  }
}

run "target_group_key_with_underscore_rejected" {
  command = plan

  variables {
    target_groups = {
      web_app = { port = 80 }
    }
  }

  expect_failures = [var.target_groups]
}

run "origin_verify_name_without_value_rejected" {
  command = plan

  variables {
    origin_verify_header_name = "X-Origin-Verify"
  }

  expect_failures = [var.origin_verify_header_name]
}

run "origin_verify_value_without_name_rejected" {
  command = plan

  variables {
    origin_verify_header_value = "not-a-real-secret"
  }

  expect_failures = [var.origin_verify_header_name]
}

run "origin_verify_name_and_value_together_accepted" {
  command = plan

  variables {
    origin_verify_header_name  = "X-Origin-Verify"
    origin_verify_header_value = "not-a-real-secret"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "A name and value given together must be accepted"
  }
}

run "target_groups_without_vpc_id_rejected" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [var.vpc_id]
}

run "empty_target_groups_without_vpc_id_accepted" {
  command = plan

  variables {
    vpc_id        = null
    target_groups = {}
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0
    error_message = "vpc_id is not required without target_groups"
  }
}
