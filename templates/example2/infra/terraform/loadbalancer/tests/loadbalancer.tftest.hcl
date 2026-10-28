mock_provider "aws" {}

variables {
  project                   = "example"
  env                       = "dev"
  expected_account_id       = "111111111111"
  origin_verify_header_name = "X-Origin-Verify"
  # A throwaway value for the tests; real values come from TF_VAR_origin_verify_header_value and never from a file.
  origin_verify_header_value = "test-only-origin-secret"
  origin_verify_host_headers = ["api.dev.example.com"]
}

# log-delivery checks that the ALB is in the current account.
override_data {
  target = module.alb_access_logs.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id              = "vpc-0123456789abcdef0"
      alb_sg_id           = "sg-0123456789abcdef0"
      alarm_topic_arn     = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      alb_certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
    }
    lists = {
      public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
}

# ---- reads ----

run "reads_only_tree_b" {
  command = plan

  assert {
    condition = local.shared_input_strings == {
      vpc_id              = "infra/vpc_id"
      alb_sg_id           = "infra/alb_sg_id"
      alarm_topic_arn     = "infra/alarm_topic_arn"
      alb_certificate_arn = "infra/alb_certificate_arn"
    } && local.shared_input_lists == { public_subnet_ids = "infra/public_subnet_ids" }
    error_message = "loadbalancer reads the VPC, the ALB security group, the alarm topic, the ALB certificate and the public subnets from tree B"
  }
}

# ---- listener rules ----

run "default_rules_are_stream_quota_admin" {
  command = plan

  assert {
    condition     = toset(keys(local.listener_rules)) == toset(["api_stream", "api_quota", "api_admin"])
    error_message = "Without the dev page there are exactly three rules"
  }

  assert {
    condition     = alltrue([for r in values(local.listener_rules) : r.target_group == "api"])
    error_message = "Every rule forwards to the api target group"
  }

  assert {
    condition     = length(distinct([for r in values(local.listener_rules) : r.priority])) == 3
    error_message = "Rule priorities must be unique"
  }
}

run "the_three_api_rules_require_the_origin_verify_header" {
  command = plan

  assert {
    condition     = alltrue([for k in ["api_stream", "api_quota", "api_admin"] : local.listener_rules[k].require_origin_verify])
    error_message = "require_origin_verify defaults to false in the alb module, so these rules must turn it on explicitly"
  }

  assert {
    condition     = alltrue([for k in ["api_stream", "api_quota", "api_admin"] : jsonencode(local.listener_rules[k].host_headers) == jsonencode(["api.dev.example.com"])])
    error_message = "The origin verify rules also match the configured host"
  }
}

run "each_api_rule_matches_its_path_and_the_subtree" {
  command = plan

  assert {
    condition = alltrue([
      for k, p in { api_stream = "/api/stream", api_quota = "/api/quota", api_admin = "/api/admin" } :
      local.listener_rules[k].path_patterns == [p, "${p}/*"]
    ])
    error_message = "A rule matches its path and everything below it"
  }
}

run "dev_page_is_off_by_default" {
  command = plan

  assert {
    condition     = !contains(keys(local.listener_rules), "dev_page")
    error_message = "dev_page_enabled defaults to false"
  }
}

run "dev_page_adds_one_rule_without_the_header_condition" {
  command = plan

  variables {
    dev_page_enabled = true
  }

  assert {
    condition     = length(local.listener_rules) == 4 && local.listener_rules["dev_page"].require_origin_verify == false
    error_message = "The dev page is a fourth rule and is reachable without the origin verify header"
  }

  assert {
    condition     = length(distinct([for r in values(local.listener_rules) : r.priority])) == 4
    error_message = "The dev page priority must not collide with the other rules"
  }
}

run "host_headers_may_be_empty" {
  command = plan

  variables {
    origin_verify_host_headers = []
  }

  assert {
    condition     = alltrue([for r in values(local.listener_rules) : length(r.host_headers) == 0 && length(r.path_patterns) == 2])
    error_message = "An empty host list leaves the rules with their path conditions only"
  }
}

# ---- target group and ALB (the real alb module plans) ----

run "alb_serves_https_with_the_certificate_from_tree_b" {
  command = plan

  assert {
    condition     = module.alb.listener_protocol == "HTTPS"
    error_message = "With the certificate from tree B the alb module opens an HTTPS:443 listener"
  }
}

# The alb module tests that HTTP:80 then only redirects to 443 with a 301; here the rules must not be on 80.
run "listener_rules_are_on_443_and_80_only_redirects" {
  command = plan

  override_resource {
    target          = module.alb.aws_lb_listener.https[0]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/example-dev-alb/0123456789abcdef/0000000000000443"
    }
  }

  override_resource {
    target          = module.alb.aws_lb_listener.http
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/example-dev-alb/0123456789abcdef/0000000000000080"
    }
  }

  assert {
    condition     = module.alb.listener_arns.https == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/example-dev-alb/0123456789abcdef/0000000000000443"
    error_message = "The HTTPS:443 listener must exist"
  }

  assert {
    condition     = module.alb.listener_arn == module.alb.listener_arns.https
    error_message = "The listener rules (origin verify, dev page) attach to 443, so 80 keeps only its redirect"
  }
}

run "alb_creates_the_api_target_group_only" {
  command = plan

  assert {
    condition     = keys(module.alb.target_group_arns) == ["api"]
    error_message = "One target group named api"
  }
}

run "alb_name_fits_the_target_group_name_limit" {
  command = plan

  assert {
    condition     = local.alb_name == "example-dev-alb" && length("${local.alb_name}-api") <= 32
    error_message = "<alb name>-api is the target group name and AWS caps it at 32 characters"
  }
}

# ---- origin verify secret ----

run "rejects_a_short_origin_verify_value" {
  command = plan

  variables {
    origin_verify_header_value = "short"
  }

  expect_failures = [var.origin_verify_header_value]
}

run "rejects_a_header_name_with_illegal_characters" {
  command = plan

  variables {
    origin_verify_header_name = "X Origin:Verify"
  }

  expect_failures = [var.origin_verify_header_name]
}

# ---- WAF ----

run "waf_redacts_the_origin_verify_header_in_lowercase" {
  command = plan

  assert {
    condition     = local.waf_logging.redacted_headers == ["x-origin-verify"]
    error_message = "The WAF log must not carry the origin verify secret; the module adds authorization and cookie itself"
  }
}

run "waf_defaults" {
  command = plan

  assert {
    condition     = local.waf_kill_switch.action == "count" && try(local.waf_kill_switch.response_json, null) == null
    error_message = "The kill switch only counts by default and has no response body"
  }

  assert {
    condition     = [for g in local.waf_managed_rule_groups : g.name] == ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
    error_message = "Common rule set first, then known bad inputs"
  }

  assert {
    condition     = contains(local.waf_managed_rule_groups[0].count_overrides, "SizeRestrictions_BODY")
    error_message = "The body size rule only counts in the common rule set; the module blocks oversized bodies itself"
  }

  assert {
    condition     = local.waf_logging.retention_days == 14
    error_message = "WAF logs are kept 14 days by default"
  }
}

run "kill_switch_block_carries_a_json_body" {
  command = plan

  variables {
    waf_kill_switch_mode = "block"
  }

  assert {
    condition     = local.waf_kill_switch.action == "block" && can(jsondecode(local.waf_kill_switch.response_json))
    error_message = "A blocking kill switch returns a JSON body"
  }
}

run "rejects_an_unknown_waf_kill_switch_mode" {
  command = plan

  variables {
    waf_kill_switch_mode = "allow"
  }

  expect_failures = [var.waf_kill_switch_mode]
}

run "rate_limit_and_allowlist_reach_the_module" {
  command = plan

  variables {
    rate_limit_per_5min        = 500
    rate_limit_allowlist_cidrs = ["198.51.100.0/24"]
  }

  assert {
    condition     = local.waf_rate_limit.limit == 500 && jsonencode(local.waf_rate_limit.allowlist_cidrs) == jsonencode(["198.51.100.0/24"])
    error_message = "The rate limit and its allowlist are passed through"
  }
}

# ---- access log bucket ----

run "access_log_bucket_follows_the_naming_pattern" {
  command = plan

  assert {
    condition     = local.access_log_bucket_name == "example-dev-alb-access-logs-111111111111"
    error_message = "Bucket names are <project>-<env>-<purpose>-<account>"
  }
}

run "access_logs_go_to_the_bucket_through_log_delivery" {
  command = plan

  override_module {
    target = module.alb
    outputs = {
      alb_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/example-dev-alb/0123456789abcdef"
      alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
      target_group_arns         = { api = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab" }
      target_group_arn_suffixes = { api = "targetgroup/example-dev-alb-api/0123456789ab" }
      alb_dns_name              = "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id               = "Z14GRHDCWA56QT"
    }
  }

  override_module {
    target = module.alb_logs
    outputs = {
      bucket_name = "example-dev-alb-access-logs-111111111111"
      arn         = "arn:aws:s3:::example-dev-alb-access-logs-111111111111"
    }
  }

  assert {
    condition = local.alb_access_logs == {
      sources      = { access = { resource_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/example-dev-alb/0123456789abcdef", log_type = "ALB_ACCESS_LOGS" } }
      destinations = { bucket = { type = "S3", resource_arn = "arn:aws:s3:::example-dev-alb-access-logs-111111111111" } }
      deliveries   = { access = { source = "access", destination = "bucket" } }
    }
    error_message = "ALB access logs must be delivered to the stack's own access log bucket"
  }
}

# ---- publishing ----

run "publishes_the_five_keys_under_the_stack_path" {
  command = plan

  override_module {
    target = module.alb
    outputs = {
      alb_arn                   = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/example-dev-alb/0123456789abcdef"
      alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
      target_group_arns         = { api = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab" }
      target_group_arn_suffixes = { api = "targetgroup/example-dev-alb-api/0123456789ab" }
      alb_dns_name              = "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id               = "Z14GRHDCWA56QT"
    }
  }

  override_module {
    target = module.waf
    outputs = {
      web_acl_arn  = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/example-dev-alb/test-web-acl-id"
      web_acl_name = "example-dev-alb"
    }
  }

  assert {
    condition = module.ssm_publish.names == {
      alb_arn_suffix            = "/example/dev/loadbalancer/alb_arn_suffix"
      target_group_arn_suffixes = "/example/dev/loadbalancer/target_group_arn_suffixes"
      api_target_group_arn      = "/example/dev/loadbalancer/api_target_group_arn"
      alb_dns_name              = "/example/dev/loadbalancer/alb_dns_name"
      alb_zone_id               = "/example/dev/loadbalancer/alb_zone_id"
    }
    error_message = "loadbalancer publishes five keys under its own path"
  }

  assert {
    condition     = local.published_strings.alb_dns_name == "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com" && local.published_strings.alb_zone_id == "Z14GRHDCWA56QT"
    error_message = "edge needs the ALB DNS name and its hosted zone ID for the origin-api alias record"
  }

  assert {
    condition     = local.published_strings.target_group_arn_suffixes == "{\"api\":\"targetgroup/example-dev-alb-api/0123456789ab\"}"
    error_message = "The suffix map is published as JSON"
  }

  assert {
    condition     = local.published_strings.api_target_group_arn == "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab"
    error_message = "application needs the full target group ARN to register the api service"
  }
}

run "alb_is_associated_with_the_web_acl_of_this_stack" {
  command = plan

  assert {
    condition     = length(module.alb.web_acl_association_ids) == 1
    error_message = "the ALB must be associated with the Web ACL created in this stack"
  }
}
