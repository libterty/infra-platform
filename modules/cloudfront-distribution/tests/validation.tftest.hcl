mock_provider "aws" {}

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
}

run "valid_inputs_pass" {
  command = plan
}

run "aliases_need_a_certificate" {
  command = plan

  variables {
    aliases         = ["app.dev.example.com"]
    certificate_arn = null
  }

  expect_failures = [var.certificate_arn]
}

run "certificate_must_be_in_us_east_1" {
  command = plan

  variables {
    aliases         = ["app.dev.example.com"]
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.certificate_arn]
}

run "certificate_must_be_acm" {
  command = plan

  variables {
    certificate_arn = "arn:aws:iam::111111111111:server-certificate/alpha"
  }

  expect_failures = [var.certificate_arn]
}

run "web_acl_must_be_global" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:ap-northeast-1:111111111111:regional/webacl/alpha-dev-waf/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.web_acl_arn]
}

run "price_class_must_be_known" {
  command = plan

  variables {
    price_class = "PriceClass_300"
  }

  expect_failures = [var.price_class]
}

run "origin_type_must_be_s3_or_custom" {
  command = plan

  variables {
    origins = {
      site = { type = "website", domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com" }
    }
  }

  expect_failures = [var.origins]
}

run "s3_origin_needs_a_bucket_domain" {
  command = plan

  variables {
    origins = {
      site = { type = "s3", domain_name = "alpha-dev-web.s3-website-ap-northeast-1.amazonaws.com" }
    }
  }

  expect_failures = [var.origins]
}

run "custom_settings_only_on_custom_origins" {
  command = plan

  variables {
    origins = {
      site = { type = "s3", domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com", custom = { https_port = 443 } }
    }
  }

  expect_failures = [var.origins]
}

run "custom_domain_has_no_scheme" {
  command = plan

  variables {
    origins = {
      site = { type = "custom", domain_name = "https://api.dev.example.com" }
    }
  }

  expect_failures = [var.origins]
}

run "custom_timeouts_in_range" {
  command = plan

  variables {
    origins = {
      site = { type = "custom", domain_name = "api.dev.example.com", custom = { read_timeout = 0 } }
    }
  }

  expect_failures = [var.origins]
}

run "origin_path_format" {
  command = plan

  variables {
    origins = {
      site = { type = "s3", domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com", origin_path = "/v1/" }
    }
  }

  expect_failures = [var.origins]
}

run "oac_name_fits_64_chars" {
  command = plan

  variables {
    origins = {
      site-with-a-very-long-origin-key-that-overflows-the-oac-name = { type = "s3", domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com" }
    }
    default_behavior = { origin = "site-with-a-very-long-origin-key-that-overflows-the-oac-name" }
  }

  expect_failures = [var.origins]
}

run "default_behavior_origin_must_exist" {
  command = plan

  variables {
    default_behavior = { origin = "missing" }
  }

  expect_failures = [var.default_behavior]
}

run "default_behavior_methods_preset" {
  command = plan

  variables {
    default_behavior = { origin = "site", allowed_methods = "write" }
  }

  expect_failures = [var.default_behavior]
}

run "policy_names_format" {
  command = plan

  variables {
    default_behavior = { origin = "site", cache_policy = "" }
  }

  expect_failures = [var.default_behavior]
}

run "ordered_behavior_origin_must_exist" {
  command = plan

  variables {
    ordered_behaviors = [
      { path_pattern = "/api/*", origin = "missing" },
    ]
  }

  expect_failures = [var.ordered_behaviors]
}

run "ordered_behavior_methods_preset" {
  command = plan

  variables {
    ordered_behaviors = [
      { path_pattern = "/api/*", origin = "site", allowed_methods = "write" },
    ]
  }

  expect_failures = [var.ordered_behaviors]
}

run "path_patterns_are_unique" {
  command = plan

  variables {
    ordered_behaviors = [
      { path_pattern = "/api/*", origin = "site" },
      { path_pattern = "/api/*", origin = "api" },
    ]
  }

  expect_failures = [var.ordered_behaviors]
}

run "origin_verify_on_s3_origin" {
  command = plan

  variables {
    origin_verify              = { origin = "site", header_name = "X-Origin-Verify" }
    origin_verify_header_value = "test-only-not-a-real-value"
  }

  expect_failures = [var.origin_verify]
}

run "origin_verify_on_missing_origin" {
  command = plan

  variables {
    origin_verify              = { origin = "missing", header_name = "X-Origin-Verify" }
    origin_verify_header_value = "test-only-not-a-real-value"
  }

  expect_failures = [var.origin_verify]
}

run "origin_verify_header_name_format" {
  command = plan

  variables {
    origin_verify              = { origin = "api", header_name = "X Origin Verify" }
    origin_verify_header_value = "test-only-not-a-real-value"
  }

  expect_failures = [var.origin_verify]
}

run "origin_verify_needs_a_value" {
  command = plan

  variables {
    origin_verify = { origin = "api", header_name = "X-Origin-Verify" }
  }

  expect_failures = [var.origin_verify]
}

run "origin_verify_value_needs_the_object" {
  command = plan

  variables {
    origin_verify_header_value = "test-only-not-a-real-value"
  }

  expect_failures = [var.origin_verify]
}

run "geo_restriction_type" {
  command = plan

  variables {
    geo_restriction = { type = "allow", locations = ["TW"] }
  }

  expect_failures = [var.geo_restriction]
}

run "geo_restriction_locations" {
  command = plan

  variables {
    geo_restriction = { type = "whitelist", locations = ["tw"] }
  }

  expect_failures = [var.geo_restriction]
}

run "default_root_object_has_no_slash" {
  command = plan

  variables {
    default_root_object = "/index.html"
  }

  expect_failures = [var.default_root_object]
}

run "name_format" {
  command = plan

  variables {
    name = "alpha dev web"
  }

  expect_failures = [var.name]
}

run "spa_function_name_fits_64_chars" {
  command = plan

  variables {
    name         = "alpha-dev-web-with-a-very-long-name-for-the-spa-fxyz"
    spa_fallback = true
  }

  expect_failures = [var.spa_fallback]
}
