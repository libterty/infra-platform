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

run "vpc_mode_by_default" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode == "VPC"
    error_message = "network_mode must default to VPC"
  }

  assert {
    condition = length(aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode_config) == 1 && (
      toset(aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode_config[0].subnets) == toset(["subnet-0aaa1111", "subnet-0bbb2222"])
      ) && (
      toset(aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode_config[0].security_groups) == toset(["sg-0ccc3333"])
    )
    error_message = "VPC mode must send the given subnets and security groups"
  }
}

run "public_mode_has_no_network_mode_config" {
  command = plan

  variables {
    network = {
      mode = "PUBLIC"
    }
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode == "PUBLIC"
    error_message = "network_mode must be PUBLIC when written out"
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.this.network_configuration[0].network_mode_config) == 0
    error_message = "PUBLIC mode must not send network_mode_config"
  }
}

run "lifecycle_defaults_sent_as_pair" {
  command = plan

  assert {
    condition = length(aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration) == 1 && (
      aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].idle_runtime_session_timeout == 900
      ) && (
      aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].max_lifetime == 28800
    )
    error_message = "lifecycle_configuration must always carry both values, defaulting to 900 and 28800"
  }
}

# Regression test for the PUT pitfall: overriding one value must still send the other.
run "lifecycle_idle_override_keeps_max_lifetime" {
  command = plan

  variables {
    session_lifecycle = {
      idle_session_timeout = 60
    }
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].idle_runtime_session_timeout == 60
    error_message = "idle_runtime_session_timeout must follow the input"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].max_lifetime == 28800
    error_message = "max_lifetime must still be sent as 28800 when only idle_session_timeout is overridden"
  }
}

run "lifecycle_max_override_keeps_idle" {
  command = plan

  variables {
    session_lifecycle = {
      max_lifetime = 3600
    }
  }

  assert {
    condition = (
      aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].idle_runtime_session_timeout == 900 &&
      aws_bedrockagentcore_agent_runtime.this.lifecycle_configuration[0].max_lifetime == 3600
    )
    error_message = "idle_runtime_session_timeout must still be sent as 900 when only max_lifetime is overridden"
  }
}

run "container_uri_and_protocol_follow_input" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.agent_runtime_artifact[0].container_configuration[0].container_uri == "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-agent:1.4.2"
    error_message = "container_uri must be sent as given"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.protocol_configuration[0].server_protocol == "HTTP"
    error_message = "server_protocol must default to HTTP"
  }

  assert {
    condition = (
      aws_bedrockagentcore_agent_runtime.this.agent_runtime_name == "alpha_dev_agent" &&
      aws_bedrockagentcore_agent_runtime.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-agent-runtime"
    )
    error_message = "name and role_arn must be sent as given"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.tags["Name"] == "alpha_dev_agent"
    error_message = "Name tag must be the runtime name"
  }
}

run "defaults_omit_optional_blocks" {
  command = plan

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.this.authorizer_configuration) == 0
    error_message = "jwt_authorizer = null must not send authorizer_configuration"
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.this.request_header_configuration) == 0
    error_message = "An empty request_header_allowlist must not send request_header_configuration"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.environment_variables == null
    error_message = "An empty environment_variables map must be sent as null"
  }
}

run "optional_blocks_follow_input" {
  command = plan

  variables {
    protocol = "MCP"
    jwt_authorizer = {
      discovery_url    = "https://idp.example.com/realms/alpha/.well-known/openid-configuration"
      allowed_audience = ["alpha-api"]
    }
    request_header_allowlist = ["X-Request-Id"]
    environment_variables = {
      LOG_LEVEL = "INFO"
    }
  }

  assert {
    condition = (
      aws_bedrockagentcore_agent_runtime.this.authorizer_configuration[0].custom_jwt_authorizer[0].discovery_url == "https://idp.example.com/realms/alpha/.well-known/openid-configuration" &&
      aws_bedrockagentcore_agent_runtime.this.authorizer_configuration[0].custom_jwt_authorizer[0].allowed_audience == toset(["alpha-api"])
    )
    error_message = "jwt_authorizer must be sent as custom_jwt_authorizer"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.request_header_configuration[0].request_header_allowlist == toset(["X-Request-Id"])
    error_message = "request_header_allowlist must be sent as given"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.environment_variables == tomap({ LOG_LEVEL = "INFO" })
    error_message = "environment_variables must be sent as given"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.protocol_configuration[0].server_protocol == "MCP"
    error_message = "server_protocol must follow protocol"
  }
}

run "a2a_protocol_accepted" {
  command = plan

  variables {
    protocol = "A2A"
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.this.protocol_configuration[0].server_protocol == "A2A"
    error_message = "server_protocol must follow protocol"
  }
}

run "outputs_expose_runtime_attributes" {
  command = plan

  override_resource {
    target          = aws_bedrockagentcore_agent_runtime.this
    override_during = plan
    values = {
      agent_runtime_arn     = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_agent-AbCdEf1234"
      agent_runtime_id      = "alpha_dev_agent-AbCdEf1234"
      agent_runtime_version = "3"
      workload_identity_details = [{
        workload_identity_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:workload-identity-directory/default/workload-identity/alpha_dev_agent-AbCdEf1234"
      }]
    }
  }

  assert {
    condition = (
      output.runtime_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_agent-AbCdEf1234" &&
      output.runtime_id == "alpha_dev_agent-AbCdEf1234" &&
      output.runtime_name == "alpha_dev_agent" &&
      output.runtime_version == "3"
    )
    error_message = "runtime outputs must come from the resource"
  }

  assert {
    condition     = output.workload_identity_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:workload-identity-directory/default/workload-identity/alpha_dev_agent-AbCdEf1234"
    error_message = "workload_identity_arn must be the first workload identity ARN"
  }
}

run "workload_identity_arn_null_when_empty" {
  command = plan

  override_resource {
    target          = aws_bedrockagentcore_agent_runtime.this
    override_during = plan
    values = {
      workload_identity_details = []
    }
  }

  assert {
    condition     = output.workload_identity_arn == null
    error_message = "workload_identity_arn must be null when no workload identity is reported"
  }
}
