mock_provider "aws" {}

# The cache and origin request policy data sources declare id as optional, not computed, so a mock cannot fill it;
# the tests check which names are looked up. The response headers policy id is computed and can be overridden.
override_data {
  target = data.aws_cloudfront_response_headers_policy.this["Managed-SecurityHeadersPolicy"]
  values = { id = "67f7725c-6f97-4210-82d7-5512b31e9d03" }
}

variables {
  name = "alpha-dev-web"
  origins = {
    site = {
      type        = "s3"
      domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com"
    }
    api = {
      type        = "custom"
      domain_name = "abcde12345.execute-api.ap-northeast-1.amazonaws.com"
    }
  }
  default_behavior = {
    origin = "site"
  }
  ordered_behaviors = [
    {
      path_pattern          = "/api/*"
      origin                = "api"
      allowed_methods       = "all"
      cache_policy          = "Managed-CachingDisabled"
      origin_request_policy = "Managed-AllViewerExceptHostHeader"
    },
  ]
  origin_verify = {
    origin      = "api"
    header_name = "X-Origin-Verify"
  }
  origin_verify_header_value = "test-only-not-a-real-value"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "custom_origin_is_https_only_with_tls12" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_origin_access_control.this) == 1 && contains(keys(aws_cloudfront_origin_access_control.this), "site")
    error_message = "Only s3 origins get an OAC"
  }

  assert {
    condition = alltrue([
      for o in nonsensitive(aws_cloudfront_distribution.this.origin) : o.origin_id != "api" || (
        o.custom_origin_config[0].origin_protocol_policy == "https-only" &&
        o.custom_origin_config[0].origin_ssl_protocols == toset(["TLSv1.2"]) &&
        o.custom_origin_config[0].https_port == 443 &&
        o.custom_origin_config[0].origin_read_timeout == 30 &&
        o.custom_origin_config[0].origin_keepalive_timeout == 5 &&
        o.origin_access_control_id == null
      )
    ])
    error_message = "A custom origin must be https-only with TLSv1.2 and default port and timeouts"
  }
}

run "origin_verify_header_is_on_the_custom_origin_and_sensitive" {
  command = plan

  assert {
    condition     = issensitive(aws_cloudfront_distribution.this.origin)
    error_message = "The origin verify value must make the plan show the origins as sensitive"
  }

  assert {
    condition = alltrue([
      for o in nonsensitive(aws_cloudfront_distribution.this.origin) :
      o.origin_id == "api" ? (
        length(o.custom_header) == 1 &&
        one(o.custom_header).name == "X-Origin-Verify" &&
        one(o.custom_header).value == "test-only-not-a-real-value"
        ) : (
        length(o.custom_header) == 0
      )
    ])
    error_message = "Only the origin_verify origin carries the header with the given value"
  }
}

run "no_origin_verify_keeps_origins_plain" {
  command = plan

  variables {
    origin_verify              = null
    origin_verify_header_value = null
  }

  assert {
    condition     = !issensitive(aws_cloudfront_distribution.this.origin)
    error_message = "Without origin verify nothing in origin is sensitive"
  }

  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.this.origin : length(o.custom_header) == 0])
    error_message = "Without origin verify no origin has a custom header"
  }
}

run "ordered_behavior_resolves_policy_names" {
  command = plan

  assert {
    condition = (
      aws_cloudfront_distribution.this.ordered_cache_behavior[0].path_pattern == "/api/*" &&
      aws_cloudfront_distribution.this.ordered_cache_behavior[0].target_origin_id == "api" &&
      aws_cloudfront_distribution.this.ordered_cache_behavior[0].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    )
    error_message = "The /api/* behavior must point at the api origin and resolve SecurityHeadersPolicy"
  }

  assert {
    condition = (
      keys(data.aws_cloudfront_cache_policy.this) == ["Managed-CachingDisabled", "Managed-CachingOptimized"] &&
      data.aws_cloudfront_cache_policy.this["Managed-CachingDisabled"].name == "Managed-CachingDisabled" &&
      keys(data.aws_cloudfront_origin_request_policy.this) == ["Managed-AllViewerExceptHostHeader"] &&
      data.aws_cloudfront_origin_request_policy.this["Managed-AllViewerExceptHostHeader"].name == "Managed-AllViewerExceptHostHeader"
    )
    error_message = "The module must look up CachingDisabled, CachingOptimized and AllViewerExceptHostHeader by name"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.ordered_cache_behavior[0].allowed_methods == toset(["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]) &&
      aws_cloudfront_distribution.this.ordered_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    )
    error_message = "allowed_methods = all must allow all seven methods and cache only GET and HEAD"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" && aws_cloudfront_distribution.this.ordered_cache_behavior[0].compress == true
    error_message = "Ordered behaviors must also redirect to HTTPS and compress"
  }

  assert {
    condition     = length(data.aws_cloudfront_cache_policy.this) == 2 && length(data.aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Each distinct policy name is looked up once"
  }
}

run "spa_fallback_leaves_the_api_behavior_alone" {
  command = plan

  variables {
    spa_fallback = true
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association) == 1
    error_message = "The default behavior must carry the SPA function"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior[0].function_association) == 0
    error_message = "The /api/* behavior must have no function association so API 403 and 404 pass through"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "No distribution-wide custom error response"
  }
}

run "read_options_preset" {
  command = plan

  variables {
    default_behavior = {
      origin          = "site"
      allowed_methods = "read_options"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods == toset(["GET", "HEAD", "OPTIONS"]) && aws_cloudfront_distribution.this.default_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    error_message = "read_options must allow GET, HEAD and OPTIONS"
  }
}

run "custom_origin_settings_are_passed_through" {
  command = plan

  variables {
    origins = {
      site = {
        type        = "s3"
        domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com"
      }
      api = {
        type        = "custom"
        domain_name = "abcde12345.execute-api.ap-northeast-1.amazonaws.com"
        origin_path = "/v1"
        custom      = { https_port = 8443, read_timeout = 60, keepalive_timeout = 10 }
      }
    }
  }

  assert {
    condition = alltrue([
      for o in nonsensitive(aws_cloudfront_distribution.this.origin) : o.origin_id != "api" || (
        o.origin_path == "/v1" &&
        o.custom_origin_config[0].https_port == 8443 &&
        o.custom_origin_config[0].origin_read_timeout == 60 &&
        o.custom_origin_config[0].origin_keepalive_timeout == 10
      )
    ])
    error_message = "origin_path, https_port and timeouts must be passed through"
  }
}

run "apply_wires_the_oac_into_the_s3_origin" {
  command = apply

  assert {
    condition = alltrue([
      for o in nonsensitive(aws_cloudfront_distribution.this.origin) :
      o.origin_access_control_id == (o.origin_id == "site" ? aws_cloudfront_origin_access_control.this["site"].id : null)
    ])
    error_message = "After apply the s3 origin must carry its OAC id and the custom origin none"
  }

  assert {
    condition     = output.oac_ids["site"] == aws_cloudfront_origin_access_control.this["site"].id
    error_message = "oac_ids must expose the OAC id"
  }
}
