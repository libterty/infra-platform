mock_provider "aws" {}

variables {
  name     = "alpha-dev-gateway"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"
  targets = {
    catalog = {
      type        = "lambda"
      description = "Catalog lookup"
      lambda_arn  = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
      tools = [
        {
          name        = "search_items"
          description = "Search items by keyword"
          properties = {
            query = { type = "string", description = "Keyword", required = true }
            limit = { type = "integer" }
          }
        },
        {
          name        = "list_categories"
          description = "List all categories"
        },
      ]
    }
    orders = {
      type               = "lambda"
      lambda_arn         = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-orders:live"
      tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/orders.json"
    }
    docs = {
      type     = "mcp_server"
      endpoint = "https://mcp.example.com/mcp"
    }
  }
}

run "gateway_is_mcp_with_iam_auth" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_gateway.this.protocol_type == "MCP"
    error_message = "protocol_type must be MCP"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_type == "AWS_IAM"
    error_message = "authorizer_type must default to AWS_IAM"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway.this.authorizer_configuration) == 0
    error_message = "AWS_IAM must not send authorizer_configuration"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.name == "alpha-dev-gateway" && aws_bedrockagentcore_gateway.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"
    error_message = "name and role_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.description == null && aws_bedrockagentcore_gateway.this.kms_key_arn == null
    error_message = "description and kms_key_arn must default to null"
  }
}

run "mcp_protocol_defaults" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_gateway.this.protocol_configuration[0].mcp[0].supported_versions == toset(["2025-03-26"])
    error_message = "supported_versions must default to 2025-03-26"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.protocol_configuration[0].mcp[0].search_type == null
    error_message = "search_type must not be sent when null"
  }
}

run "mcp_search_type_passed" {
  command = plan

  variables {
    mcp = { search_type = "SEMANTIC", supported_versions = ["2025-03-26", "2025-06-18"] }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.protocol_configuration[0].mcp[0].search_type == "SEMANTIC"
    error_message = "search_type must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.protocol_configuration[0].mcp[0].supported_versions == toset(["2025-03-26", "2025-06-18"])
    error_message = "supported_versions must follow the input"
  }
}

run "description_kms_and_tags" {
  command = plan

  variables {
    description = "Tools for the agent"
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    tags        = { Project = "alpha" }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.description == "Tools for the agent"
    error_message = "description must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "kms_key_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-gateway" })
    error_message = "tags must be the input plus Name"
  }
}

run "custom_jwt_authorizer" {
  command = plan

  variables {
    authorizer = {
      type             = "CUSTOM_JWT"
      discovery_url    = "https://idp.example.com/.well-known/openid-configuration"
      allowed_audience = ["alpha-gateway"]
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_type == "CUSTOM_JWT"
    error_message = "authorizer_type must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_configuration[0].custom_jwt_authorizer[0].discovery_url == "https://idp.example.com/.well-known/openid-configuration"
    error_message = "CUSTOM_JWT must send discovery_url"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_configuration[0].custom_jwt_authorizer[0].allowed_audience == toset(["alpha-gateway"])
    error_message = "CUSTOM_JWT must send allowed_audience"
  }
  assert {
    condition     = length(coalesce(aws_bedrockagentcore_gateway.this.authorizer_configuration[0].custom_jwt_authorizer[0].allowed_clients, [])) == 0
    error_message = "allowed_clients must be empty when not given"
  }
}

run "custom_jwt_clients_only" {
  command = plan

  variables {
    authorizer = {
      type            = "CUSTOM_JWT"
      discovery_url   = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_clients = ["client-a"]
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_configuration[0].custom_jwt_authorizer[0].allowed_clients == toset(["client-a"])
    error_message = "CUSTOM_JWT must send allowed_clients"
  }
}

run "one_target_per_entry" {
  command = plan

  assert {
    condition     = toset(keys(aws_bedrockagentcore_gateway_target.this)) == toset(["catalog", "orders", "docs"])
    error_message = "Expected one target per entry"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].name == "catalog" && aws_bedrockagentcore_gateway_target.this["docs"].name == "docs"
    error_message = "Target name must be the map key"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].description == "Catalog lookup" && aws_bedrockagentcore_gateway_target.this["orders"].description == null
    error_message = "Target description must follow the input"
  }
}

run "lambda_target_uses_gateway_role" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].lambda_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
    error_message = "lambda_arn must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["orders"].target_configuration[0].mcp[0].lambda[0].lambda_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-orders:live"
    error_message = "lambda_arn with a qualifier must follow the input"
  }
  assert {
    condition = alltrue([for k in ["catalog", "orders"] :
      length(aws_bedrockagentcore_gateway_target.this[k].credential_provider_configuration) == 1 &&
      length(aws_bedrockagentcore_gateway_target.this[k].credential_provider_configuration[0].gateway_iam_role) == 1
    ])
    error_message = "Lambda targets must use the gateway_iam_role credential"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].mcp_server) == 0
    error_message = "A lambda target must not have an mcp_server block"
  }
}

run "inline_tools_become_inline_payload" {
  command = plan

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload) == 2
    error_message = "Each tool must be one inline_payload block"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].s3) == 0
    error_message = "tools must not send tool_schema.s3"
  }
  assert {
    condition = (
      aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].name == "search_items" &&
      aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].description == "Search items by keyword"
    )
    error_message = "Tool name and description must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].input_schema[0].type == "object"
    error_message = "input_schema type must be object"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].input_schema[0].property) == 2
    error_message = "Each property must be one property block"
  }
  assert {
    condition = anytrue([for p in aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].input_schema[0].property :
      p.name == "query" && p.type == "string" && p.description == "Keyword" && p.required == true
    ])
    error_message = "Property query must carry its type, description and required flag"
  }
  assert {
    condition = anytrue([for p in aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].input_schema[0].property :
      p.name == "limit" && p.type == "integer" && p.required == false
    ])
    error_message = "Property limit must carry its type and default required to false"
  }
  assert {
    condition = (
      aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[1].input_schema[0].type == "object" &&
      length(aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[1].input_schema[0].property) == 0
    )
    error_message = "A tool without properties must still send an empty object input_schema"
  }
}

run "s3_schema_has_no_inline_payload" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["orders"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].s3[0].uri == "s3://alpha-dev-tool-schemas/orders.json"
    error_message = "tool_schema.s3.uri must follow tool_schema_s3_uri"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["orders"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload) == 0
    error_message = "tool_schema_s3_uri must not send inline_payload"
  }
}

run "mcp_server_target_has_no_credential" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["docs"].target_configuration[0].mcp[0].mcp_server[0].endpoint == "https://mcp.example.com/mcp"
    error_message = "endpoint must follow the input"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["docs"].credential_provider_configuration) == 0
    error_message = "An mcp_server target must not send credential_provider_configuration"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["docs"].target_configuration[0].mcp[0].lambda) == 0
    error_message = "An mcp_server target must not have a lambda block"
  }
  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["docs"].target_configuration[0].mcp[0].mcp_server[0].mcp_tool_schema) == 0
    error_message = "An mcp_server target must not send a tool schema"
  }
}

run "no_targets" {
  command = plan

  variables {
    targets = {}
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 0
    error_message = "targets = {} must create no target"
  }
  assert {
    condition     = length(output.target_ids) == 0
    error_message = "target_ids must be empty without targets"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_bedrockagentcore_gateway.this
    override_during = plan
    values = {
      gateway_id  = "alpha-dev-gateway-abc123"
      gateway_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abc123"
      gateway_url = "https://alpha-dev-gateway-abc123.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp"
    }
  }
  override_resource {
    target          = aws_bedrockagentcore_gateway_target.this["catalog"]
    override_during = plan
    values          = { target_id = "TCATALOG" }
  }
  override_resource {
    target          = aws_bedrockagentcore_gateway_target.this["orders"]
    override_during = plan
    values          = { target_id = "TORDERS" }
  }
  override_resource {
    target          = aws_bedrockagentcore_gateway_target.this["docs"]
    override_during = plan
    values          = { target_id = "TDOCS" }
  }

  assert {
    condition     = alltrue([for t in aws_bedrockagentcore_gateway_target.this : t.gateway_identifier == "alpha-dev-gateway-abc123"])
    error_message = "Targets must attach to the gateway id"
  }
  assert {
    condition     = output.gateway_id == "alpha-dev-gateway-abc123"
    error_message = "gateway_id must expose the gateway id"
  }
  assert {
    condition     = output.gateway_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abc123"
    error_message = "gateway_arn must expose the gateway ARN"
  }
  assert {
    condition     = output.gateway_url == "https://alpha-dev-gateway-abc123.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp"
    error_message = "gateway_url must expose the gateway URL"
  }
  assert {
    condition     = output.target_ids == tomap({ catalog = "TCATALOG", orders = "TORDERS", docs = "TDOCS" })
    error_message = "target_ids must map target keys to target ids"
  }
}
