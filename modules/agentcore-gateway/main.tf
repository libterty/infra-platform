resource "aws_bedrockagentcore_gateway" "this" {
  name            = var.name
  description     = var.description
  role_arn        = var.role_arn
  kms_key_arn     = var.kms_key_arn
  protocol_type   = "MCP"
  authorizer_type = var.authorizer.type

  dynamic "authorizer_configuration" {
    for_each = var.authorizer.type == "CUSTOM_JWT" ? [var.authorizer] : []
    content {
      custom_jwt_authorizer {
        discovery_url    = authorizer_configuration.value.discovery_url
        allowed_audience = length(authorizer_configuration.value.allowed_audience) > 0 ? authorizer_configuration.value.allowed_audience : null
        allowed_clients  = length(authorizer_configuration.value.allowed_clients) > 0 ? authorizer_configuration.value.allowed_clients : null
      }
    }
  }

  protocol_configuration {
    mcp {
      supported_versions = var.mcp.supported_versions
      search_type        = var.mcp.search_type
    }
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_bedrockagentcore_gateway_target" "this" {
  for_each = var.targets

  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id
  name               = each.key
  description        = each.value.description

  # The gateway calls the Lambda with its own role. MCP server targets get no
  # outbound credential because credential providers are out of scope.
  dynamic "credential_provider_configuration" {
    for_each = each.value.type == "lambda" ? [1] : []
    content {
      gateway_iam_role {}
    }
  }

  target_configuration {
    mcp {
      dynamic "lambda" {
        for_each = each.value.type == "lambda" ? [each.value] : []
        content {
          lambda_arn = lambda.value.lambda_arn

          tool_schema {
            dynamic "s3" {
              for_each = lambda.value.tool_schema_s3_uri != null ? [lambda.value.tool_schema_s3_uri] : []
              content {
                uri = s3.value
              }
            }

            dynamic "inline_payload" {
              for_each = coalesce(lambda.value.tools, [])
              content {
                name        = inline_payload.value.name
                description = inline_payload.value.description

                input_schema {
                  type = "object"

                  dynamic "property" {
                    for_each = inline_payload.value.properties
                    content {
                      name        = property.key
                      type        = property.value.type
                      description = property.value.description
                      required    = property.value.required
                    }
                  }
                }
              }
            }
          }
        }
      }

      dynamic "mcp_server" {
        for_each = each.value.type == "mcp_server" ? [each.value.endpoint] : []
        content {
          endpoint = mcp_server.value
        }
      }
    }
  }
}
