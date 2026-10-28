mock_provider "aws" {}

variables {
  project                   = "example"
  env                       = "dev"
  expected_account_id       = "111111111111"
  origin_verify_header_name = "X-Origin-Verify"
  # A throwaway value for the tests; real values come from TF_VAR_origin_verify_header_value and never from a file.
  origin_verify_header_value = "test-only-origin-secret"
  waf_rate_limit_per_5min    = 2000
  log_retention_days         = 30
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_id"]
  values = { insecure_value = "Z0000000000000000000A" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
  values = { insecure_value = "dev.example.com" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["certificate/web_certificate_arn"]
  values = { insecure_value = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["api/api_endpoint"]
  values = { insecure_value = "a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com" }
}

# The distribution and the WAF outputs are unknown in a plan; fixed values make the wiring checkable.
override_module {
  target = module.cdn
  outputs = {
    distribution_id = "E0000000000001"
    arn             = "arn:aws:cloudfront::111111111111:distribution/E0000000000001"
    domain_name     = "d1234567890abc.cloudfront.net"
    hosted_zone_id  = "Z2FDTNDATAQYW2"
    oac_ids         = { site = "E0000000000OAC" }
  }
}

override_module {
  target = module.waf
  outputs = {
    web_acl_arn    = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/example-dev-web/00000000-0000-0000-0000-000000000000"
    web_acl_name   = "example-dev-web"
    ip_set_arn     = null
    log_group_name = "aws-waf-logs-example-dev-web"
  }
}

override_module {
  target = module.site_bucket
  outputs = {
    bucket_name                 = "example-dev-web-111111111111"
    arn                         = "arn:aws:s3:::example-dev-web-111111111111"
    bucket_regional_domain_name = "example-dev-web-111111111111.s3.ap-northeast-1.amazonaws.com"
  }
}

# log-delivery and s3-bucket compare ARNs with the current account; the mock would return a random one.
override_data {
  target = module.cdn_logs.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.log_bucket.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

run "reads_only_earlier_stack_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      zone_id             = "dns/zone_id"
      zone_name           = "dns/zone_name"
      web_certificate_arn = "certificate/web_certificate_arn"
      api_endpoint        = "api/api_endpoint"
    } && local.ssm_input_lists == {}
    error_message = "web may read only the dns, certificate and api keys it needs (design 8.2)"
  }
}

# Design 4: CloudFront reaches S3 through OAC and the bucket policy names only this distribution.
run "bucket_policy_allows_only_this_distribution" {
  command = plan

  assert {
    condition     = local.site_bucket_readers == ["arn:aws:cloudfront::111111111111:distribution/E0000000000001"]
    error_message = "The site bucket must let exactly this distribution read it"
  }

  assert {
    condition     = length(regexall("cloudfront_distribution_arns", join("\n", [for f in fileset(path.module, "*.tf") : file("${path.module}/${f}")]))) == 1 && length(regexall("(?m)^\\s*cloudfront_distribution_arns\\s*=\\s*local\\.site_bucket_readers\\s*$", file("${path.module}/buckets.tf"))) == 1
    error_message = "Only the site bucket may grant CloudFront access, and only to local.site_bucket_readers"
  }

  assert {
    condition     = local.site_bucket.name == "example-dev-web-111111111111" && local.site_bucket.never_expire
    error_message = "The site bucket keeps its files until they are replaced"
  }

  assert {
    condition     = !strcontains(file("${path.module}/buckets.tf"), "kms_key_arn")
    error_message = "Both buckets use SSE-S3 (design 5.8): CloudFront and log delivery cannot use the shared key"
  }

  assert {
    condition     = local.cdn.origins["site"] == { type = "s3", domain_name = "example-dev-web-111111111111.s3.ap-northeast-1.amazonaws.com" }
    error_message = "The site origin must be the bucket's regional domain, so the module puts an OAC on it"
  }
}

# Design K14: the WAF is always on, in CLOUDFRONT scope, and attached to the distribution.
run "waf_is_cloudfront_scope_and_attached" {
  command = plan

  assert {
    condition     = local.waf.scope == "CLOUDFRONT"
    error_message = "The WAF must be in CLOUDFRONT scope"
  }

  assert {
    condition     = local.cdn.web_acl_arn == "arn:aws:wafv2:us-east-1:111111111111:global/webacl/example-dev-web/00000000-0000-0000-0000-000000000000"
    error_message = "The distribution must use the web ACL of this stack"
  }

  assert {
    condition = (
      [for g in local.waf.managed_rule_groups : g.name] == ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"] &&
      local.waf.rate_limit == { limit = 2000 }
    )
    error_message = "The WAF must have the managed rules and the tfvars rate limit"
  }

  assert {
    condition     = local.waf.logging.redacted_headers == ["x-origin-verify"] && local.waf.logging.retention_days == 30
    error_message = "The WAF log must redact the origin verify header"
  }
}

# Design K16 and K17: /api/* goes to the API uncached, without the viewer Host, and carries the origin verify header.
run "api_behavior_carries_origin_verify" {
  command = plan

  assert {
    condition = local.cdn.ordered_behaviors == [{
      path_pattern          = "/api/*"
      origin                = "api"
      allowed_methods       = "all"
      cache_policy          = "Managed-CachingDisabled"
      origin_request_policy = "Managed-AllViewerExceptHostHeader"
    }]
    error_message = "/api/* must go to the api origin with all methods, CachingDisabled and AllViewerExceptHostHeader"
  }

  assert {
    condition     = local.cdn.origins["api"] == { type = "custom", domain_name = "a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com" }
    error_message = "The api origin must be the execute-api host the api stack publishes"
  }

  assert {
    condition     = local.cdn.origin_verify == { origin = "api", header_name = "X-Origin-Verify" }
    error_message = "The origin verify header must be added on the api origin, the one /api/* uses"
  }

  assert {
    condition     = issensitive(var.origin_verify_header_value)
    error_message = "The origin verify value must be sensitive"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*origin_verify_header_value\\s*=\\s*var\\.origin_verify_header_value\\s*$", file("${path.module}/distribution.tf"))) == 1
    error_message = "The distribution must get the value from the sensitive variable"
  }
}

run "distribution_settings" {
  command = plan

  assert {
    condition = (
      local.cdn.name == "example-dev-web" &&
      local.cdn.aliases == ["app.dev.example.com"] &&
      local.cdn.certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000" &&
      local.cdn.price_class == "PriceClass_200" &&
      local.cdn.default_behavior == { origin = "site" } &&
      local.cdn.default_root_object == "index.html" &&
      local.cdn.spa_fallback
    )
    error_message = "The distribution serves app.<zone> with the us-east-1 certificate, PriceClass_200 and the SPA from S3"
  }
}

run "app_records_point_at_the_distribution" {
  command = plan

  assert {
    condition = local.app_records == {
      a    = { name = "app.dev.example.com", type = "A", alias = { name = "d1234567890abc.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" } }
      aaaa = { name = "app.dev.example.com", type = "AAAA", alias = { name = "d1234567890abc.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" } }
    }
    error_message = "app.<zone> must alias the distribution for IPv4 and IPv6"
  }
}

# Design 5.5: CloudFront logs go through log-delivery from us-east-1 into the log bucket.
run "cloudfront_logs_go_to_the_log_bucket" {
  command = plan

  override_module {
    target = module.log_bucket
    outputs = {
      bucket_name                 = "example-dev-cdn-logs-111111111111"
      arn                         = "arn:aws:s3:::example-dev-cdn-logs-111111111111"
      bucket_regional_domain_name = "example-dev-cdn-logs-111111111111.s3.ap-northeast-1.amazonaws.com"
    }
  }

  assert {
    condition = local.cdn_logs == {
      region       = "us-east-1"
      sources      = { access = { resource_arn = "arn:aws:cloudfront::111111111111:distribution/E0000000000001", log_type = "ACCESS_LOGS" } }
      destinations = { bucket = { type = "S3", resource_arn = "arn:aws:s3:::example-dev-cdn-logs-111111111111" } }
      deliveries   = { access = { source = "access", destination = "bucket" } }
    }
    error_message = "The distribution access logs must be delivered from us-east-1 to the log bucket"
  }

  assert {
    condition     = local.log_bucket == { name = "example-dev-cdn-logs-111111111111", log_delivery = ["vended_logs"], expiration_days = 30 }
    error_message = "The log bucket must accept vended logs and expire them after the tfvars retention"
  }
}

run "publishes_the_deploy_targets" {
  command = plan

  assert {
    condition     = local.published_strings == { site_bucket_name = "example-dev-web-111111111111", distribution_id = "E0000000000001" }
    error_message = "web must publish the site bucket and the distribution ID for the SPA deploy"
  }

  assert {
    condition     = module.ssm_publish.names == { site_bucket_name = "/example/dev/web/site_bucket_name", distribution_id = "/example/dev/web/distribution_id" }
    error_message = "ssm-publish must write the keys under the web path"
  }
}

run "origin_verify_value_too_short_rejected" {
  command = plan

  variables {
    origin_verify_header_value = "short"
  }

  expect_failures = [var.origin_verify_header_value]
}

run "origin_verify_header_name_rejected" {
  command = plan

  variables {
    origin_verify_header_name = "X Origin Verify"
  }

  expect_failures = [var.origin_verify_header_name]
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
