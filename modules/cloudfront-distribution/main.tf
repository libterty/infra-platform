locals {
  allowed_methods = {
    read         = ["GET", "HEAD"]
    read_options = ["GET", "HEAD", "OPTIONS"]
    all          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
  }

  behaviors = concat([var.default_behavior], var.ordered_behaviors)

  cache_policy_names            = toset([for b in local.behaviors : b.cache_policy if b.cache_policy != null])
  origin_request_policy_names   = toset([for b in local.behaviors : b.origin_request_policy if b.origin_request_policy != null])
  response_headers_policy_names = toset([for b in local.behaviors : b.response_headers_policy if b.response_headers_policy != null])

  custom_defaults = { https_port = 443, read_timeout = 30, keepalive_timeout = 5 }

  s3_origins = { for k, o in var.origins : k => o if o.type == "s3" }
}

data "aws_cloudfront_cache_policy" "this" {
  for_each = local.cache_policy_names
  name     = each.key
}

data "aws_cloudfront_origin_request_policy" "this" {
  for_each = local.origin_request_policy_names
  name     = each.key
}

data "aws_cloudfront_response_headers_policy" "this" {
  for_each = local.response_headers_policy_names
  name     = each.key
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.s3_origins

  name                              = "${var.name}-${each.key}"
  description                       = "OAC for origin ${each.key} of ${var.name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_fallback" {
  count = var.spa_fallback ? 1 : 0

  name    = "${var.name}-spa-fallback"
  comment = "Rewrites extension-less paths to /index.html for ${var.name}"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/spa-fallback.js")
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = coalesce(var.comment, var.name)
  aliases             = var.aliases
  price_class         = var.price_class
  web_acl_id          = var.web_acl_arn
  default_root_object = var.default_root_object
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  dynamic "origin" {
    for_each = var.origins
    content {
      origin_id                = origin.key
      domain_name              = origin.value.domain_name
      origin_path              = origin.value.origin_path
      origin_access_control_id = origin.value.type == "s3" ? aws_cloudfront_origin_access_control.this[origin.key].id : null

      dynamic "custom_origin_config" {
        for_each = origin.value.type == "custom" ? [origin.value.custom != null ? origin.value.custom : local.custom_defaults] : []
        content {
          http_port                = 80
          https_port               = custom_origin_config.value.https_port
          origin_protocol_policy   = "https-only"
          origin_ssl_protocols     = ["TLSv1.2"]
          origin_read_timeout      = custom_origin_config.value.read_timeout
          origin_keepalive_timeout = custom_origin_config.value.keepalive_timeout
        }
      }

      # for_each only reads the non-sensitive origin_verify object; the sensitive value is used in content only,
      # so Terraform can still expand the block while the plan hides the value.
      dynamic "custom_header" {
        for_each = try(var.origin_verify.origin, null) == origin.key ? [var.origin_verify.header_name] : []
        content {
          name  = custom_header.value
          value = var.origin_verify_header_value
        }
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = var.default_behavior.origin
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    allowed_methods            = local.allowed_methods[var.default_behavior.allowed_methods]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = var.default_behavior.cache_policy == null ? null : data.aws_cloudfront_cache_policy.this[var.default_behavior.cache_policy].id
    origin_request_policy_id   = var.default_behavior.origin_request_policy == null ? null : data.aws_cloudfront_origin_request_policy.this[var.default_behavior.origin_request_policy].id
    response_headers_policy_id = var.default_behavior.response_headers_policy == null ? null : data.aws_cloudfront_response_headers_policy.this[var.default_behavior.response_headers_policy].id

    # Only the default behavior serves the SPA; ordered behaviors such as /api/* keep their own 403 and 404.
    dynamic "function_association" {
      for_each = aws_cloudfront_function.spa_fallback
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value.arn
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_behaviors
    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = ordered_cache_behavior.value.origin
      viewer_protocol_policy     = "redirect-to-https"
      compress                   = true
      allowed_methods            = local.allowed_methods[ordered_cache_behavior.value.allowed_methods]
      cached_methods             = ["GET", "HEAD"]
      cache_policy_id            = ordered_cache_behavior.value.cache_policy == null ? null : data.aws_cloudfront_cache_policy.this[ordered_cache_behavior.value.cache_policy].id
      origin_request_policy_id   = ordered_cache_behavior.value.origin_request_policy == null ? null : data.aws_cloudfront_origin_request_policy.this[ordered_cache_behavior.value.origin_request_policy].id
      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy == null ? null : data.aws_cloudfront_response_headers_policy.this[ordered_cache_behavior.value.response_headers_policy].id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction == null ? "none" : var.geo_restriction.type
      locations        = var.geo_restriction == null ? [] : var.geo_restriction.locations
    }
  }

  # The CloudFront default certificate ignores the minimum protocol version, so the TLS policy applies with an ACM
  # certificate only.
  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == null
    acm_certificate_arn            = var.certificate_arn
    minimum_protocol_version       = var.certificate_arn == null ? null : "TLSv1.2_2021"
    ssl_support_method             = var.certificate_arn == null ? null : "sni-only"
  }

  tags = merge(var.tags, { Name = var.name })
}
