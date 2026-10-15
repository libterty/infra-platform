mock_provider "aws" {}

variables {
  name     = "alpha-dev-gateway"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"
}

run "name_100_chars_accepted" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc" # 100 chars
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.name == "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc"
    error_message = "A 100 char name must pass"
  }
}

run "name_101_chars_rejected" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc" # 101 chars
  }

  expect_failures = [var.name]
}

run "name_double_hyphen_rejected" {
  command = plan

  variables {
    name = "alpha--gateway"
  }

  expect_failures = [var.name]
}

run "name_trailing_hyphen_rejected" {
  command = plan

  variables {
    name = "alpha-gateway-"
  }

  expect_failures = [var.name]
}

run "name_underscore_rejected" {
  command = plan

  variables {
    name = "alpha_gateway"
  }

  expect_failures = [var.name]
}

run "role_arn_with_path_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:role/service-role/alpha-dev-gateway"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_not_a_role_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/alpha"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_other_partition_accepted" {
  command = plan

  variables {
    role_arn = "arn:aws-cn:iam::111111111111:role/alpha-dev-gateway"
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.role_arn == "arn:aws-cn:iam::111111111111:role/alpha-dev-gateway"
    error_message = "A role ARN in another partition must pass"
  }
}

run "authorizer_none_rejected" {
  command = plan

  variables {
    authorizer = { type = "NONE" }
  }

  expect_failures = [var.authorizer]
}

run "custom_jwt_without_discovery_url_rejected" {
  command = plan

  variables {
    authorizer = { type = "CUSTOM_JWT", allowed_audience = ["alpha"] }
  }

  expect_failures = [var.authorizer]
}

run "custom_jwt_discovery_url_wrong_suffix_rejected" {
  command = plan

  variables {
    authorizer = { type = "CUSTOM_JWT", discovery_url = "https://idp.example.com/jwks.json", allowed_audience = ["alpha"] }
  }

  expect_failures = [var.authorizer]
}

run "custom_jwt_discovery_url_http_rejected" {
  command = plan

  variables {
    authorizer = { type = "CUSTOM_JWT", discovery_url = "http://idp.example.com/.well-known/openid-configuration", allowed_audience = ["alpha"] }
  }

  expect_failures = [var.authorizer]
}

run "custom_jwt_without_audience_or_clients_rejected" {
  command = plan

  variables {
    authorizer = { type = "CUSTOM_JWT", discovery_url = "https://idp.example.com/.well-known/openid-configuration" }
  }

  expect_failures = [var.authorizer]
}

run "aws_iam_with_discovery_url_rejected" {
  command = plan

  variables {
    authorizer = { type = "AWS_IAM", discovery_url = "https://idp.example.com/.well-known/openid-configuration" }
  }

  expect_failures = [var.authorizer]
}

run "aws_iam_with_audience_rejected" {
  command = plan

  variables {
    authorizer = { type = "AWS_IAM", allowed_audience = ["alpha"] }
  }

  expect_failures = [var.authorizer]
}

run "aws_iam_with_clients_rejected" {
  command = plan

  variables {
    authorizer = { type = "AWS_IAM", allowed_clients = ["client-a"] }
  }

  expect_failures = [var.authorizer]
}

run "target_key_100_chars_accepted" {
  command = plan

  variables {
    targets = {
      abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 1
    error_message = "A 100 char target name must pass"
  }
}

run "target_key_double_hyphen_rejected" {
  command = plan

  variables {
    targets = {
      "tools--a" = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  expect_failures = [var.targets]
}

run "target_key_101_chars_rejected" {
  command = plan

  variables {
    targets = {
      abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  expect_failures = [var.targets]
}

run "target_type_open_api_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "open_api", endpoint = "https://api.example.com" }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_without_lambda_arn_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_arn_not_a_function_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:layer:alpha", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_with_endpoint_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }], endpoint = "https://mcp.example.com" }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_with_both_schemas_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }], tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/tools.json" }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_with_no_schema_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools" }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_with_empty_tools_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [] }
    }
  }

  expect_failures = [var.targets]
}

run "lambda_with_s3_schema_only_accepted" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/tools.json" }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 1
    error_message = "A lambda target with only tool_schema_s3_uri must pass"
  }
}

run "lambda_with_tools_only_accepted" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 1
    error_message = "A lambda target with only tools must pass"
  }
}

run "mcp_server_with_lambda_arn_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server", endpoint = "https://mcp.example.com/mcp", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools" }
    }
  }

  expect_failures = [var.targets]
}

run "mcp_server_with_tools_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server", endpoint = "https://mcp.example.com/mcp", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  expect_failures = [var.targets]
}

run "mcp_server_with_s3_schema_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server", endpoint = "https://mcp.example.com/mcp", tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/tools.json" }
    }
  }

  expect_failures = [var.targets]
}

run "mcp_server_without_endpoint_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server" }
    }
  }

  expect_failures = [var.targets]
}

run "mcp_server_http_endpoint_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server", endpoint = "http://mcp.example.com/mcp" }
    }
  }

  expect_failures = [var.targets]
}

run "mcp_server_https_endpoint_accepted" {
  command = plan

  variables {
    targets = {
      tools = { type = "mcp_server", endpoint = "https://mcp.example.com:8443" }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 1
    error_message = "An https endpoint must pass"
  }
}

run "s3_uri_not_s3_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tool_schema_s3_uri = "https://alpha-dev-tool-schemas.s3.amazonaws.com/tools.json" }
    }
  }

  expect_failures = [var.targets]
}

run "s3_uri_without_key_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tool_schema_s3_uri = "s3://alpha-dev-tool-schemas" }
    }
  }

  expect_failures = [var.targets]
}

run "property_type_date_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up", properties = { day = { type = "date" } } }] }
    }
  }

  expect_failures = [var.targets]
}

run "property_basic_types_accepted" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up", properties = { string_value = { type = "string" }, number_value = { type = "number" }, integer_value = { type = "integer" }, boolean_value = { type = "boolean" }, object_value = { type = "object" }, array_value = { type = "array" } } }] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this["tools"].target_configuration[0].mcp[0].lambda[0].tool_schema[0].inline_payload[0].input_schema[0].property) == 6
    error_message = "All six JSON Schema basic types must pass"
  }
}

run "duplicate_tool_names_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "A" }, { name = "lookup", description = "B" }] }
    }
  }

  expect_failures = [var.targets]
}

run "same_tool_name_in_two_targets_accepted" {
  command = plan

  variables {
    targets = {
      a = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
      b = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "Look up" }] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_gateway_target.this) == 2
    error_message = "The same tool name in different targets must pass"
  }
}

run "empty_tool_description_rejected" {
  command = plan

  variables {
    targets = {
      tools = { type = "lambda", lambda_arn = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-tools", tools = [{ name = "lookup", description = "  " }] }
    }
  }

  expect_failures = [var.targets]
}
