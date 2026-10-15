mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  name     = "alpha-dev-gateway"
  role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway"
}

# Same-account guard on Lambda targets

run "lambda_same_account_accepted" {
  command = plan

  variables {
    targets = {
      catalog = {
        type               = "lambda"
        lambda_arn         = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
        tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/catalog.json"
      }
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].lambda_arn == "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-catalog"
    error_message = "A Lambda in the current account must pass"
  }
}

run "lambda_other_account_rejected" {
  command = plan

  variables {
    targets = {
      catalog = {
        type               = "lambda"
        lambda_arn         = "arn:aws:lambda:ap-northeast-1:222222222222:function:alpha-dev-catalog"
        tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/catalog.json"
      }
    }
  }

  expect_failures = [aws_bedrockagentcore_gateway_target.this]
}

run "lambda_other_account_listed_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
    targets = {
      catalog = {
        type               = "lambda"
        lambda_arn         = "arn:aws:lambda:ap-northeast-1:222222222222:function:alpha-dev-catalog"
        tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/catalog.json"
      }
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["catalog"].target_configuration[0].mcp[0].lambda[0].lambda_arn == "arn:aws:lambda:ap-northeast-1:222222222222:function:alpha-dev-catalog"
    error_message = "A Lambda in an account listed in allowed_account_ids must pass"
  }
}

run "lambda_other_account_not_listed_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["333333333333"]
    targets = {
      catalog = {
        type               = "lambda"
        lambda_arn         = "arn:aws:lambda:ap-northeast-1:222222222222:function:alpha-dev-catalog"
        tool_schema_s3_uri = "s3://alpha-dev-tool-schemas/catalog.json"
      }
    }
  }

  expect_failures = [aws_bedrockagentcore_gateway_target.this]
}

run "mcp_server_target_not_account_checked" {
  command = plan

  variables {
    targets = {
      docs = {
        type     = "mcp_server"
        endpoint = "https://mcp.example.com/mcp"
      }
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway_target.this["docs"].target_configuration[0].mcp[0].mcp_server[0].endpoint == "https://mcp.example.com/mcp"
    error_message = "An mcp_server target carries no account and must pass"
  }
}

run "allowed_account_ids_not_12_digits_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["22222222222"]
  }

  expect_failures = [var.allowed_account_ids]
}

run "allowed_account_ids_12_digits_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
  }
}

# JWT entries must not be blank

run "jwt_blank_audience_rejected" {
  command = plan

  variables {
    authorizer = {
      type             = "CUSTOM_JWT"
      discovery_url    = "https://idp.example.com/.well-known/openid-configuration"
      allowed_audience = ["alpha-gateway", ""]
    }
  }

  expect_failures = [var.authorizer]
}

run "jwt_whitespace_audience_rejected" {
  command = plan

  variables {
    authorizer = {
      type             = "CUSTOM_JWT"
      discovery_url    = "https://idp.example.com/.well-known/openid-configuration"
      allowed_audience = ["  "]
    }
  }

  expect_failures = [var.authorizer]
}

run "jwt_whitespace_client_rejected" {
  command = plan

  variables {
    authorizer = {
      type            = "CUSTOM_JWT"
      discovery_url   = "https://idp.example.com/.well-known/openid-configuration"
      allowed_clients = ["client-a", "\t"]
    }
  }

  expect_failures = [var.authorizer]
}

run "jwt_non_blank_entries_accepted" {
  command = plan

  variables {
    authorizer = {
      type             = "CUSTOM_JWT"
      discovery_url    = "https://idp.example.com/.well-known/openid-configuration"
      allowed_audience = ["alpha-gateway"]
      allowed_clients  = ["client-a"]
    }
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.authorizer_configuration[0].custom_jwt_authorizer[0].allowed_clients == toset(["client-a"])
    error_message = "Non-blank audience and clients must pass"
  }
}

# kms_key_arn format

run "kms_key_arn_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "A KMS key ARN must pass"
  }
}

run "kms_key_arn_multi_region_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = aws_bedrockagentcore_gateway.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
    error_message = "A KMS key ARN must pass"
  }
}

run "kms_key_arn_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_bare_key_id_rejected" {
  command = plan

  variables {
    kms_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.kms_key_arn]
}
