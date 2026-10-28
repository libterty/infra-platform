locals {
  disable_execute_api_endpoint = coalesce(var.disable_execute_api_endpoint, var.custom_domain != null)

  # Fixed so every API logs the same fields; no JWT claims or headers, which may carry personal data.
  access_log_format = jsonencode({
    requestId          = "$context.requestId"
    requestTime        = "$context.requestTime"
    ip                 = "$context.identity.sourceIp"
    userAgent          = "$context.identity.userAgent"
    httpMethod         = "$context.httpMethod"
    routeKey           = "$context.routeKey"
    path               = "$context.path"
    protocol           = "$context.protocol"
    status             = "$context.status"
    responseLength     = "$context.responseLength"
    responseLatency    = "$context.responseLatency"
    integrationLatency = "$context.integrationLatency"
    integrationStatus  = "$context.integrationStatus"
    integrationError   = "$context.integrationErrorMessage"
    authorizerError    = "$context.authorizer.error"
    domainName         = "$context.domainName"
  })
}

resource "aws_apigatewayv2_api" "this" {
  name                         = var.name
  description                  = var.description
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = local.disable_execute_api_endpoint

  dynamic "cors_configuration" {
    for_each = var.cors == null ? [] : [var.cors]
    content {
      allow_origins     = cors_configuration.value.allow_origins
      allow_methods     = cors_configuration.value.allow_methods
      allow_headers     = cors_configuration.value.allow_headers
      allow_credentials = cors_configuration.value.allow_credentials
      max_age           = cors_configuration.value.max_age
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_apigatewayv2_authorizer" "this" {
  for_each = var.jwt_authorizers

  api_id           = aws_apigatewayv2_api.this.id
  name             = each.key
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = each.value.issuer
    audience = each.value.audience
  }
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = var.integrations

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = each.value.lambda_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = each.value.timeout_ms
}

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.this[each.value.integration].id}"

  authorization_type   = each.value.public ? "NONE" : "JWT"
  authorizer_id        = each.value.public ? null : aws_apigatewayv2_authorizer.this[each.value.authorizer].id
  authorization_scopes = length(each.value.scopes) == 0 ? null : each.value.scopes
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttling.rate_limit
    throttling_burst_limit = var.throttling.burst_limit
  }

  access_log_settings {
    destination_arn = var.access_log_group_arn
    format          = local.access_log_format
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_apigatewayv2_domain_name" "this" {
  count = var.custom_domain == null ? 0 : 1

  domain_name = var.custom_domain.domain_name

  domain_name_configuration {
    certificate_arn = var.custom_domain.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = merge(var.tags, { Name = var.custom_domain.domain_name })
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.custom_domain == null ? 0 : 1

  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.this.id
}
