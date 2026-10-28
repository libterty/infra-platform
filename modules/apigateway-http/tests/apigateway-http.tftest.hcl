mock_provider "aws" {}

override_resource {
  target = aws_apigatewayv2_api.this
  values = {
    id            = "a1b2c3d4e5"
    api_endpoint  = "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com"
    execution_arn = "arn:aws:execute-api:ap-northeast-1:111111111111:a1b2c3d4e5"
  }
}

override_resource {
  target = aws_apigatewayv2_stage.this
  values = {
    id         = "$default"
    invoke_url = "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com/"
  }
}

override_resource {
  target = aws_apigatewayv2_domain_name.this
  values = {
    domain_name_configuration = {
      target_domain_name = "d-abc123.execute-api.ap-northeast-1.amazonaws.com"
      hosted_zone_id     = "Z1YSHQZHG15GKL"
    }
  }
}

variables {
  name = "alpha-dev-api"

  jwt_authorizers = {
    cognito = {
      issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
      audience = ["1example23456789"]
    }
  }

  integrations = {
    items = {
      lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-items"
    }
  }

  routes = {
    "GET /items" = {
      integration = "items"
      authorizer  = "cognito"
      scopes      = ["alpha/items.read"]
    }
    "GET /health" = {
      integration = "items"
      public      = true
    }
  }

  throttling = {
    rate_limit  = 50
    burst_limit = 100
  }

  access_log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/apigateway/alpha-dev-api"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "http_api_defaults" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.this.name == "alpha-dev-api" && aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "The API must be an HTTP API with the given name"
  }

  assert {
    condition     = aws_apigatewayv2_api.this.disable_execute_api_endpoint == false
    error_message = "Without a custom domain the execute-api endpoint must stay enabled"
  }

  assert {
    condition     = length(aws_apigatewayv2_api.this.cors_configuration) == 0
    error_message = "No CORS configuration may be created when cors is null"
  }

  assert {
    condition     = length(aws_apigatewayv2_domain_name.this) == 0 && length(aws_apigatewayv2_api_mapping.this) == 0
    error_message = "No custom domain may be created when custom_domain is null"
  }
}

run "default_stage_with_throttling_and_access_log" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.this.name == "$default" && aws_apigatewayv2_stage.this.auto_deploy == true
    error_message = "The stage must be $default with auto deploy"
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.default_route_settings[0].throttling_rate_limit == 50 && aws_apigatewayv2_stage.this.default_route_settings[0].throttling_burst_limit == 100
    error_message = "Stage throttling must come from var.throttling"
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.access_log_settings[0].destination_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/apigateway/alpha-dev-api"
    error_message = "Access logs must go to the given log group"
  }

  assert {
    condition     = jsondecode(aws_apigatewayv2_stage.this.access_log_settings[0].format).requestId == "$context.requestId" && jsondecode(aws_apigatewayv2_stage.this.access_log_settings[0].format).status == "$context.status"
    error_message = "The access log format must be the fixed JSON format"
  }
}

run "lambda_proxy_integration" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_integration.this["items"].integration_type == "AWS_PROXY" && aws_apigatewayv2_integration.this["items"].payload_format_version == "2.0"
    error_message = "Integrations must be Lambda proxy with payload 2.0"
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["items"].integration_uri == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-items" && aws_apigatewayv2_integration.this["items"].timeout_milliseconds == 30000
    error_message = "Integration must target the given Lambda with the default 30 s timeout"
  }
}

run "jwt_authorizer" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_authorizer.this["cognito"].authorizer_type == "JWT"
    error_message = "Authorizers must be JWT"
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.this["cognito"].jwt_configuration[0].issuer == "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI" && aws_apigatewayv2_authorizer.this["cognito"].jwt_configuration[0].audience == toset(["1example23456789"])
    error_message = "Issuer and audience must be passed through"
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.this["cognito"].identity_sources == toset(["$request.header.Authorization"])
    error_message = "The token must come from the Authorization header"
  }
}

run "jwt_route_and_public_route" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items"].authorization_type == "JWT" && aws_apigatewayv2_route.this["GET /items"].authorizer_id == aws_apigatewayv2_authorizer.this["cognito"].id
    error_message = "A route with an authorizer must use JWT with that authorizer"
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items"].authorization_scopes == toset(["alpha/items.read"])
    error_message = "Route scopes must be passed through"
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /health"].authorization_type == "NONE" && aws_apigatewayv2_route.this["GET /health"].authorizer_id == null
    error_message = "A public route must have no authorizer"
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /health"].target == "integrations/${aws_apigatewayv2_integration.this["items"].id}"
    error_message = "Routes must target their integration"
  }
}

run "custom_domain_disables_execute_api_by_default" {
  command = apply

  variables {
    custom_domain = {
      domain_name     = "api.dev.example.com"
      certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
    }
  }

  assert {
    condition     = aws_apigatewayv2_api.this.disable_execute_api_endpoint == true
    error_message = "With a custom domain the execute-api endpoint must be disabled by default"
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.this[0].domain_name == "api.dev.example.com" && aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].endpoint_type == "REGIONAL" && aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].security_policy == "TLS_1_2"
    error_message = "The custom domain must be regional with TLS 1.2"
  }

  assert {
    condition     = aws_apigatewayv2_api_mapping.this[0].api_id == "a1b2c3d4e5" && aws_apigatewayv2_api_mapping.this[0].stage == "$default"
    error_message = "The API mapping must point the domain at the $default stage"
  }

  assert {
    condition     = output.domain_target == { name = "d-abc123.execute-api.ap-northeast-1.amazonaws.com", zone_id = "Z1YSHQZHG15GKL" }
    error_message = "domain_target must expose the regional target for an alias record"
  }
}

run "execute_api_endpoint_can_stay_enabled_with_custom_domain" {
  command = plan

  variables {
    custom_domain = {
      domain_name     = "api.dev.example.com"
      certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/1234abcd-12ab-34cd-56ef-1234567890ab"
    }
    disable_execute_api_endpoint = false
  }

  assert {
    condition     = aws_apigatewayv2_api.this.disable_execute_api_endpoint == false
    error_message = "An explicit false must win over the custom domain default"
  }
}

run "cors_is_passed_through" {
  command = plan

  variables {
    cors = {
      allow_origins     = ["https://app.dev.example.com"]
      allow_methods     = ["GET", "POST"]
      allow_headers     = ["authorization", "content-type"]
      allow_credentials = true
      max_age           = 300
    }
  }

  assert {
    condition     = aws_apigatewayv2_api.this.cors_configuration[0].allow_origins == toset(["https://app.dev.example.com"]) && aws_apigatewayv2_api.this.cors_configuration[0].allow_credentials == true && aws_apigatewayv2_api.this.cors_configuration[0].max_age == 300
    error_message = "CORS settings must be passed through"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.api_id == "a1b2c3d4e5" && output.api_endpoint == "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com"
    error_message = "api_id and api_endpoint must come from the API"
  }

  assert {
    condition     = output.execution_arn == "arn:aws:execute-api:ap-northeast-1:111111111111:a1b2c3d4e5"
    error_message = "execution_arn must come from the API"
  }

  assert {
    condition     = output.stage_invoke_url == "https://a1b2c3d4e5.execute-api.ap-northeast-1.amazonaws.com/"
    error_message = "stage_invoke_url must come from the stage"
  }

  assert {
    condition     = output.domain_target == null
    error_message = "domain_target must be null without a custom domain"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "route_without_authorizer_or_public_rejected" {
  command = plan

  variables {
    routes = {
      "GET /items" = { integration = "items" }
    }
  }

  expect_failures = [var.routes]
}

run "route_with_authorizer_and_public_rejected" {
  command = plan

  variables {
    routes = {
      "GET /items" = { integration = "items", authorizer = "cognito", public = true }
    }
  }

  expect_failures = [var.routes]
}

run "unknown_authorizer_key_rejected" {
  command = plan

  variables {
    routes = {
      "GET /items" = { integration = "items", authorizer = "missing" }
    }
  }

  expect_failures = [var.routes]
}

run "unknown_integration_key_rejected" {
  command = plan

  variables {
    routes = {
      "GET /items" = { integration = "missing", authorizer = "cognito" }
    }
  }

  expect_failures = [var.routes]
}

run "scopes_on_public_route_rejected" {
  command = plan

  variables {
    routes = {
      "GET /health" = { integration = "items", public = true, scopes = ["alpha/items.read"] }
    }
  }

  expect_failures = [var.routes]
}

run "malformed_route_key_rejected" {
  command = plan

  variables {
    routes = {
      "items" = { integration = "items", authorizer = "cognito" }
    }
  }

  expect_failures = [var.routes]
}

run "empty_routes_rejected" {
  command = plan

  variables {
    routes = {}
  }

  expect_failures = [var.routes]
}

run "allow_credentials_with_wildcard_origin_rejected" {
  command = plan

  variables {
    cors = {
      allow_origins     = ["*"]
      allow_credentials = true
    }
  }

  expect_failures = [var.cors]
}

run "http_issuer_rejected" {
  command = plan

  variables {
    jwt_authorizers = {
      cognito = {
        issuer   = "http://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
        audience = ["1example23456789"]
      }
    }
  }

  expect_failures = [var.jwt_authorizers]
}

run "empty_audience_rejected" {
  command = plan

  variables {
    jwt_authorizers = {
      cognito = {
        issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI"
        audience = []
      }
    }
  }

  expect_failures = [var.jwt_authorizers]
}

run "timeout_below_50_rejected" {
  command = plan

  variables {
    integrations = {
      items = {
        lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-items"
        timeout_ms = 49
      }
    }
  }

  expect_failures = [var.integrations]
}

run "timeout_above_30000_rejected" {
  command = plan

  variables {
    integrations = {
      items = {
        lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-items"
        timeout_ms = 30001
      }
    }
  }

  expect_failures = [var.integrations]
}

run "non_lambda_integration_arn_rejected" {
  command = plan

  variables {
    integrations = {
      items = {
        lambda_arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-items"
      }
    }
  }

  expect_failures = [var.integrations]
}

run "zero_rate_limit_rejected" {
  command = plan

  variables {
    throttling = {
      rate_limit  = 0
      burst_limit = 100
    }
  }

  expect_failures = [var.throttling]
}

run "negative_burst_limit_rejected" {
  command = plan

  variables {
    throttling = {
      rate_limit  = 50
      burst_limit = -1
    }
  }

  expect_failures = [var.throttling]
}

run "throttling_is_required" {
  command = plan

  variables {
    throttling = null
  }

  expect_failures = [var.throttling]
}

run "access_log_group_arn_is_required" {
  command = plan

  variables {
    access_log_group_arn = null
  }

  expect_failures = [var.access_log_group_arn]
}

run "access_log_group_arn_with_wildcard_suffix_rejected" {
  command = plan

  variables {
    access_log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/apigateway/alpha-dev-api:*"
  }

  expect_failures = [var.access_log_group_arn]
}

run "custom_domain_with_non_acm_arn_rejected" {
  command = plan

  variables {
    custom_domain = {
      domain_name     = "api.dev.example.com"
      certificate_arn = "arn:aws:iam::111111111111:server-certificate/alpha"
    }
  }

  expect_failures = [var.custom_domain]
}

run "name_with_spaces_rejected" {
  command = plan

  variables {
    name = "alpha dev api"
  }

  expect_failures = [var.name]
}
