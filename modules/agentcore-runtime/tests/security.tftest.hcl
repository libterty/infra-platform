mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  name          = "alpha_dev_agent"
  role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-agent-runtime"
  container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
  network = {
    subnet_ids         = ["subnet-0aaa1111", "subnet-0bbb2222"]
    security_group_ids = ["sg-0ccc3333"]
  }
}

# latest in any letter case

run "container_uri_rejects_latest_upper_case" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:LATEST"
  }

  expect_failures = [var.container_uri]
}

run "container_uri_rejects_latest_mixed_case" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:Latest"
  }

  expect_failures = [var.container_uri]
}

run "container_uri_accepts_tag_containing_latest" {
  command = plan

  variables {
    container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:latest-1.4.2"
  }
}

# Same-account guard on the image registry

run "container_uri_rejects_other_account" {
  command = plan

  variables {
    container_uri = "222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
  }

  expect_failures = [aws_bedrockagentcore_agent_runtime.this]
}

run "container_uri_accepts_listed_account" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
    container_uri       = "222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.agent_runtime_artifact[0].container_configuration[0].container_uri == "222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
    error_message = "An image in an account listed in allowed_account_ids must pass"
  }
}

run "container_uri_rejects_unlisted_account" {
  command = plan

  variables {
    allowed_account_ids = ["333333333333"]
    container_uri       = "222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
  }

  expect_failures = [aws_bedrockagentcore_agent_runtime.this]
}

run "allowed_account_ids_rejects_non_12_digits" {
  command = plan

  variables {
    allowed_account_ids = ["2222222222222"]
  }

  expect_failures = [var.allowed_account_ids]
}

run "allowed_account_ids_accepts_12_digits" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
  }
}

# JWT entries must not be blank

run "jwt_rejects_blank_audience" {
  command = plan

  variables {
    jwt_authorizer = {
      discovery_url    = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_audience = ["alpha-api", ""]
    }
  }

  expect_failures = [var.jwt_authorizer]
}

run "jwt_rejects_whitespace_client" {
  command = plan

  variables {
    jwt_authorizer = {
      discovery_url   = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_clients = ["  "]
    }
  }

  expect_failures = [var.jwt_authorizer]
}

run "jwt_accepts_non_blank_entries" {
  command = plan

  variables {
    jwt_authorizer = {
      discovery_url    = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_audience = ["alpha-api"]
      allowed_clients  = ["alpha-web"]
    }
  }
}

# Credential-bearing request headers

run "header_rejects_authorization" {
  command = plan

  variables {
    request_header_allowlist = ["Authorization"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_accepts_authorization_with_jwt_authorizer" {
  command = plan

  variables {
    jwt_authorizer = {
      discovery_url    = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_audience = ["alpha-api"]
    }
    request_header_allowlist = ["Authorization"]
  }
}

run "header_rejects_cookie_with_jwt_authorizer" {
  command = plan

  variables {
    jwt_authorizer = {
      discovery_url    = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_audience = ["alpha-api"]
    }
    request_header_allowlist = ["Authorization", "Cookie"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_rejects_cookie_lower_case" {
  command = plan

  variables {
    request_header_allowlist = ["X-Request-Id", "cookie"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_rejects_proxy_authorization" {
  command = plan

  variables {
    request_header_allowlist = ["Proxy-Authorization"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_rejects_host" {
  command = plan

  variables {
    request_header_allowlist = ["HOST"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_rejects_amz_security_token" {
  command = plan

  variables {
    request_header_allowlist = ["x-amz-security-token"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_rejects_amz_date" {
  command = plan

  variables {
    request_header_allowlist = ["X-Amz-Date"]
  }

  expect_failures = [var.request_header_allowlist]
}

run "header_accepts_custom_headers" {
  command = plan

  variables {
    request_header_allowlist = ["X-Request-Id", "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant"]
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.request_header_configuration[0].request_header_allowlist == toset(["X-Request-Id", "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant"])
    error_message = "Headers that carry no credentials must pass"
  }
}

# Secret-looking environment variable names

run "env_rejects_password" {
  command = plan

  variables {
    environment_variables = { LOG_LEVEL = "INFO", DB_PASSWORD = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_lower_case_api_key" {
  command = plan

  variables {
    environment_variables = { vendor_api_key = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_apikey_without_underscore" {
  command = plan

  variables {
    environment_variables = { VENDORAPIKEY = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_secret" {
  command = plan

  variables {
    environment_variables = { CLIENT_SECRET = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_passwd" {
  command = plan

  variables {
    environment_variables = { SMTP_PASSWD = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_token" {
  command = plan

  variables {
    environment_variables = { GitHub_Token = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_private_key" {
  command = plan

  variables {
    environment_variables = { SIGNING_PRIVATEKEY = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_rejects_credential" {
  command = plan

  variables {
    environment_variables = { SERVICE_CREDENTIALS = "x" }
  }

  expect_failures = [var.environment_variables]
}

run "env_accepts_plain_names" {
  command = plan

  variables {
    environment_variables = { LOG_LEVEL = "INFO", TRACELOOP_TRACE_CONTENT = "false" }
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.environment_variables == tomap({ LOG_LEVEL = "INFO", TRACELOOP_TRACE_CONTENT = "false" })
    error_message = "Plain environment variable names must pass"
  }
}

run "env_accepts_secret_arn_name" {
  command = plan

  variables {
    environment_variables = { DB_SECRET_ARN = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev-db-AbCdEf" }
  }
}

run "env_rejects_arn_name_with_non_arn_value" {
  command = plan

  variables {
    environment_variables = { DB_SECRET_ARN = "hunter2" }
  }

  expect_failures = [var.environment_variables]
}
