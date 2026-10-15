# The image is not ignored on purpose: Terraform owns the tag, so an image swapped outside Terraform is rolled back on the next apply.
resource "aws_bedrockagentcore_agent_runtime" "this" {
  agent_runtime_name = var.name
  description        = var.description
  role_arn           = var.role_arn
  # An empty map would be read back as null and show a diff on every plan.
  environment_variables = length(var.environment_variables) > 0 ? var.environment_variables : null

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_uri
    }
  }

  network_configuration {
    network_mode = var.network.mode

    dynamic "network_mode_config" {
      for_each = var.network.mode == "VPC" ? [var.network] : []
      content {
        subnets         = network_mode_config.value.subnet_ids
        security_groups = network_mode_config.value.security_group_ids
      }
    }
  }

  # UpdateAgentRuntime replaces the whole lifecycle configuration; a value left out silently reverts to the AWS default.
  lifecycle_configuration = [{
    idle_runtime_session_timeout = var.session_lifecycle.idle_session_timeout
    max_lifetime                 = var.session_lifecycle.max_lifetime
  }]

  protocol_configuration {
    server_protocol = var.protocol
  }

  dynamic "authorizer_configuration" {
    for_each = var.jwt_authorizer == null ? [] : [var.jwt_authorizer]
    content {
      custom_jwt_authorizer {
        discovery_url    = authorizer_configuration.value.discovery_url
        allowed_audience = length(authorizer_configuration.value.allowed_audience) > 0 ? authorizer_configuration.value.allowed_audience : null
        allowed_clients  = length(authorizer_configuration.value.allowed_clients) > 0 ? authorizer_configuration.value.allowed_clients : null
      }
    }
  }

  dynamic "request_header_configuration" {
    for_each = length(var.request_header_allowlist) > 0 ? [var.request_header_allowlist] : []
    content {
      request_header_allowlist = request_header_configuration.value
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
