mock_provider "aws" {}

override_data {
  target = data.aws_cloudfront_response_headers_policy.this["Managed-SecurityHeadersPolicy"]
  values = { id = "67f7725c-6f97-4210-82d7-5512b31e9d03" }
}

# Computed values are unknown at plan; override_during = plan lets plan-time runs read them.
override_resource {
  target          = aws_cloudfront_distribution.this
  override_during = plan
  values = {
    id             = "E1ABCDEFGHIJKL"
    arn            = "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"
    domain_name    = "d111111abcdef8.cloudfront.net"
    hosted_zone_id = "Z2FDTNDATAQYW2"
  }
}

override_resource {
  target          = aws_cloudfront_function.spa_fallback
  override_during = plan
  values = {
    arn = "arn:aws:cloudfront::111111111111:function/alpha-dev-web-spa-fallback"
  }
}

override_resource {
  target          = aws_cloudfront_origin_access_control.this
  override_during = plan
  values = {
    id = "E2OACABCDEFGHI"
  }
}

variables {
  name            = "alpha-dev-web"
  aliases         = ["app.dev.example.com"]
  certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  web_acl_arn     = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/alpha-dev-edge/11111111-2222-3333-4444-555555555555"
  origins = {
    site = {
      type        = "s3"
      domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com"
    }
  }
  default_behavior = {
    origin = "site"
  }
  default_root_object = "index.html"
  spa_fallback        = true
}

# ---- positive -------------------------------------------------------------------------------------------------

run "s3_origin_gets_an_oac" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_origin_access_control.this) == 1 && aws_cloudfront_origin_access_control.this["site"].name == "alpha-dev-web-site"
    error_message = "Each s3 origin needs one OAC named <name>-<origin key>"
  }

  assert {
    condition = (
      aws_cloudfront_origin_access_control.this["site"].origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.this["site"].signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.this["site"].signing_protocol == "sigv4"
    )
    error_message = "The OAC must sign every request with sigv4 for s3"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_access_control_id == "E2OACABCDEFGHI" && one(aws_cloudfront_distribution.this.origin).origin_id == "site"
    error_message = "The s3 origin must use its OAC"
  }

  assert {
    condition     = length(one(aws_cloudfront_distribution.this.origin).custom_origin_config) == 0 && length(one(aws_cloudfront_distribution.this.origin).custom_header) == 0
    error_message = "An s3 origin has no custom origin config and no custom header"
  }
}

run "fixed_viewer_settings" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" && aws_cloudfront_distribution.this.default_cache_behavior[0].compress == true
    error_message = "Viewers must be redirected to HTTPS and responses compressed"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/11111111-2222-3333-4444-555555555555" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only"
    )
    error_message = "The viewer certificate must be the ACM cert with TLSv1.2_2021 and sni-only"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.http_version == "http2and3" && aws_cloudfront_distribution.this.is_ipv6_enabled == true && aws_cloudfront_distribution.this.enabled == true
    error_message = "http2and3 and IPv6 must be on"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_200"
    error_message = "price_class must default to PriceClass_200"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == "arn:aws:wafv2:us-east-1:111111111111:global/webacl/alpha-dev-edge/11111111-2222-3333-4444-555555555555"
    error_message = "web_acl_id must be the given web ACL ARN"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["app.dev.example.com"]) && aws_cloudfront_distribution.this.default_root_object == "index.html"
    error_message = "aliases and default_root_object must be passed through"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "alpha-dev-web"
    error_message = "comment must default to name"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "none"
    error_message = "No geo_restriction means restriction_type none"
  }
}

run "default_behavior_uses_managed_policies" {
  command = plan

  assert {
    condition     = keys(data.aws_cloudfront_cache_policy.this) == ["Managed-CachingOptimized"] && data.aws_cloudfront_cache_policy.this["Managed-CachingOptimized"].name == "Managed-CachingOptimized"
    error_message = "The default cache policy must be Managed-CachingOptimized"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    error_message = "The default response headers policy must be Managed-SecurityHeadersPolicy"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].origin_request_policy_id == null && length(data.aws_cloudfront_origin_request_policy.this) == 0
    error_message = "No origin request policy unless one is named"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods == toset(["GET", "HEAD"]) && aws_cloudfront_distribution.this.default_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    error_message = "allowed_methods must default to read (GET, HEAD)"
  }
}

run "spa_fallback_attaches_a_viewer_request_function_to_the_default_behavior" {
  command = plan

  assert {
    condition = (
      length(aws_cloudfront_function.spa_fallback) == 1 &&
      aws_cloudfront_function.spa_fallback[0].name == "alpha-dev-web-spa-fallback" &&
      aws_cloudfront_function.spa_fallback[0].runtime == "cloudfront-js-2.0" &&
      aws_cloudfront_function.spa_fallback[0].publish == true &&
      strcontains(aws_cloudfront_function.spa_fallback[0].code, "/index.html")
    )
    error_message = "spa_fallback must create one published cloudfront-js-2.0 function named <name>-spa-fallback"
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association) == 1 &&
      one(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association).event_type == "viewer-request" &&
      one(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association).function_arn == "arn:aws:cloudfront::111111111111:function/alpha-dev-web-spa-fallback"
    )
    error_message = "The function must be attached to the default behavior as viewer-request"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "spa_fallback must not use distribution-wide custom error responses"
  }
}

run "no_spa_fallback_by_default" {
  command = plan

  variables {
    spa_fallback = false
  }

  assert {
    condition     = length(aws_cloudfront_function.spa_fallback) == 0 && length(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association) == 0
    error_message = "spa_fallback = false must create and attach no function"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "spa_fallback = false must add no custom error response"
  }
}

run "geo_restriction_is_passed_through" {
  command = plan

  variables {
    geo_restriction = { type = "whitelist", locations = ["TW", "JP"] }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "whitelist" && aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations == toset(["TW", "JP"])
    error_message = "geo_restriction must be passed through"
  }
}

run "default_certificate_without_aliases" {
  command = plan

  variables {
    aliases         = []
    certificate_arn = null
    web_acl_arn     = null
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate == true && aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == null
    error_message = "Without a certificate the distribution uses the CloudFront default certificate"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == null
    error_message = "web_acl_arn = null means no web ACL"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-web" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.distribution_id == "E1ABCDEFGHIJKL" &&
      output.arn == "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL" &&
      output.domain_name == "d111111abcdef8.cloudfront.net" &&
      output.hosted_zone_id == "Z2FDTNDATAQYW2" &&
      length(output.oac_ids) == 1 && output.oac_ids["site"] == "E2OACABCDEFGHI"
    )
    error_message = "Outputs must expose the distribution and OAC ids"
  }
}
