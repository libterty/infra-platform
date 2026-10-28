mock_provider "aws" {}

variables {
  project                   = "example"
  env                       = "dev"
  expected_account_id       = "111111111111"
  origin_verify_header_name = "X-Origin-Verify"
  # A throwaway value for the tests; real values come from TF_VAR_origin_verify_header_value and never from a file.
  origin_verify_header_value = "test-only-origin-secret"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alb_dns_name = "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id  = "Z14GRHDCWA56QT"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      zone_id                    = "Z0123456789ABCDEFGHIJ"
      zone_name                  = "dev.example.com"
      cloudfront_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
    }
  }
}

# The distribution and the WAF outputs are unknown in a plan; fixed values make the wiring checkable.
override_module {
  target = module.cdn
  outputs = {
    distribution_id = "E0000000000001"
    arn             = "arn:aws:cloudfront::111111111111:distribution/E0000000000001"
    domain_name     = "d1234567890abc.cloudfront.net"
    hosted_zone_id  = "Z2FDTNDATAQYW2"
    oac_ids         = {}
  }
}

override_module {
  target = module.waf
  outputs = {
    web_acl_arn    = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/example-dev-api-edge/00000000-0000-0000-0000-000000000000"
    web_acl_name   = "example-dev-api-edge"
    ip_set_arn     = null
    log_group_name = "aws-waf-logs-example-dev-api-edge"
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

# ---- reads ----

run "reads_tree_b_and_the_loadbalancer_keys_only" {
  command = plan

  assert {
    condition = local.shared_input_strings == {
      zone_id                    = "infra/zone_id"
      zone_name                  = "infra/zone_name"
      cloudfront_certificate_arn = "infra/cloudfront_certificate_arn"
    }
    error_message = "edge reads the zone and the CloudFront certificate from tree B"
  }

  assert {
    condition = local.ssm_input_strings == {
      alb_dns_name = "loadbalancer/alb_dns_name"
      alb_zone_id  = "loadbalancer/alb_zone_id"
    }
    error_message = "edge reads only the ALB DNS name and zone ID from tree A, both published by loadbalancer"
  }
}

# ---- WAF (design K9) ----

run "waf_is_cloudfront_scope_and_attached" {
  command = plan

  assert {
    condition     = local.waf.scope == "CLOUDFRONT"
    error_message = "The edge WAF must be in CLOUDFRONT scope"
  }

  assert {
    condition     = local.cdn.web_acl_arn == "arn:aws:wafv2:us-east-1:111111111111:global/webacl/example-dev-api-edge/00000000-0000-0000-0000-000000000000"
    error_message = "The distribution must use the web ACL of this stack"
  }

  assert {
    condition     = [for g in local.waf.managed_rule_groups : g.name] == ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
    error_message = "Common rule set first, then known bad inputs, as on the ALB WAF"
  }

  assert {
    condition     = contains(local.waf.managed_rule_groups[0].count_overrides, "SizeRestrictions_BODY") && jsonencode(local.waf.body_size_exempt_path_prefixes) == jsonencode(["/api/admin"])
    error_message = "The edge must exempt the same paths from the body size limit as the ALB WAF, or it blocks admin uploads"
  }

  assert {
    condition     = local.waf.rate_limit.limit == 2000 && length(local.waf.rate_limit.allowlist_cidrs) == 0
    error_message = "The rate limit counts client IPs at 2000 per five minutes by default"
  }

  assert {
    condition     = local.waf.logging.redacted_headers == ["x-origin-verify"] && local.waf.logging.retention_days == 14
    error_message = "The WAF log must redact the origin verify header"
  }
}

# ---- distribution (design K7, K8) ----

run "origin_is_the_alb_over_https_only" {
  command = plan

  assert {
    condition     = keys(local.cdn.origins) == ["alb"] && local.cdn.origins["alb"].type == "custom"
    error_message = "One custom origin; cloudfront-distribution fixes custom origins to https-only with TLSv1.2"
  }

  assert {
    condition     = local.cdn.origins["alb"].domain_name == "origin-api.dev.example.com"
    error_message = "CloudFront reaches the ALB as origin-api.<zone>, a name the ALB certificate covers"
  }

  assert {
    condition     = !strcontains(join("\n", [for f in fileset(path.module, "*.tf") : file("${path.module}/${f}")]), "http-only")
    error_message = "Nothing in the stack may ask for an http-only origin"
  }
}

run "default_behavior_forwards_the_viewer_host_uncached" {
  command = plan

  assert {
    condition = local.cdn.default_behavior == {
      origin                = "alb"
      allowed_methods       = "all"
      cache_policy          = "Managed-CachingDisabled"
      origin_request_policy = "Managed-AllViewer"
    }
    error_message = "Everything goes to the ALB with all methods, no caching and the viewer Host (AllViewer), so the ALB host rules match"
  }
}

run "origin_verify_value_is_sensitive" {
  command = plan

  assert {
    condition     = local.cdn.origin_verify == { origin = "alb", header_name = "X-Origin-Verify" }
    error_message = "The origin verify header goes on the ALB origin with the same name the loadbalancer stack checks"
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
      local.cdn.name == "example-dev-api" &&
      local.cdn.aliases == ["api.dev.example.com"] &&
      local.cdn.certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002" &&
      local.cdn.price_class == "PriceClass_200"
    )
    error_message = "The distribution serves api.<zone> with the us-east-1 certificate from tree B and PriceClass_200"
  }

  assert {
    condition     = !strcontains(file("${path.module}/distribution.tf"), "spa_fallback") && !strcontains(file("${path.module}/distribution.tf"), "ordered_behaviors")
    error_message = "An API has no SPA fallback and needs no other behaviors"
  }
}

# ---- records ----

run "records_alias_api_to_cloudfront_and_origin_api_to_the_alb" {
  command = plan

  assert {
    condition = local.dns_records == {
      api_a        = { name = "api.dev.example.com", type = "A", alias = { name = "d1234567890abc.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" } }
      api_aaaa     = { name = "api.dev.example.com", type = "AAAA", alias = { name = "d1234567890abc.cloudfront.net", zone_id = "Z2FDTNDATAQYW2" } }
      origin_api_a = { name = "origin-api.dev.example.com", type = "A", alias = { name = "example-dev-alb-123.ap-northeast-1.elb.amazonaws.com", zone_id = "Z14GRHDCWA56QT" } }
    }
    error_message = "api.<zone> must alias the distribution (IPv4 and IPv6) and origin-api.<zone> the ALB"
  }
}

# ---- logs ----

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
    condition     = local.log_bucket == { name = "example-dev-cdn-logs-111111111111", log_delivery = ["vended_logs"], expiration_days = 14 }
    error_message = "The log bucket must accept vended logs and follow <project>-<env>-<purpose>-<account>"
  }

  assert {
    condition     = !strcontains(file("${path.module}/logs.tf"), "kms_key_arn")
    error_message = "The log bucket uses SSE-S3: log delivery cannot write with a CMK that has no key policy for it"
  }
}

# ---- publishing (design 7.3) ----

run "publishes_the_distribution_id_and_domain_name" {
  command = plan

  assert {
    condition     = local.published_strings == { distribution_id = "E0000000000001", domain_name = "d1234567890abc.cloudfront.net" }
    error_message = "edge publishes the distribution ID and its domain name"
  }

  assert {
    condition     = module.ssm_publish.names == { distribution_id = "/example/dev/edge/distribution_id", domain_name = "/example/dev/edge/domain_name" }
    error_message = "ssm-publish must write the keys under the edge path"
  }
}

# ---- variables ----

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
