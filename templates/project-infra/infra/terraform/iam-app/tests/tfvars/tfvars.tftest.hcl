# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_rds_proxy_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-rds-proxy" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
  values = { insecure_value = "{}" }
}


override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/models"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/guardrails"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/agent_memories"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/knowledge_bases"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/agentcore_gateway"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["agent/bedrock_invoke"]
  values = { insecure_value = "{\"enabled\":false}" }
}

# The Runtime "assistant" and the service roles; read only by the runs that publish them.
override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["agent/agent_runtime_assistant"]
  values = { insecure_value = "{\"arn\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj\",\"id\":\"alpha_dev_assistant-AbCdEfGhIj\",\"name\":\"alpha_dev_assistant\",\"execution_role_arn\":\"arn:aws:iam::111111111111:role/alpha-dev-agent-assistant\",\"models\":[\"chat\"],\"memories\":[\"conversation\"],\"guardrails\":[\"safety\",\"english\"],\"knowledge_bases\":[\"products\"],\"gateway\":true,\"tracing\":true}" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agent_assistant_execution_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_bedrock_kb_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agentcore_gateway_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/data_access"]
  values = { insecure_value = "{\"db\":[\"api\",\"worker\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = {
    insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"has_reader\":false,\"cluster_arn\":\"arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db\",\"data_api\":true}"
  }
}

run "tfvars_create_a_task_role_per_service" {
  command = plan

  assert {
    condition     = length(module.task_role) == 2 && length(module.proxy_secret_access) == 1
    error_message = "Every service needs a task role and the Proxy role needs its secret policy"
  }

  assert {
    condition     = alltrue([for s in var.ecs_exec_services : contains(["api", "worker"], s)])
    error_message = "ecs_exec_services in tfvars must name known services"
  }
}

run "tfvars_tracing_names_known_services" {
  command = plan

  assert {
    condition     = alltrue([for s in var.tracing : contains(["api", "worker"], s)])
    error_message = "tracing in tfvars must name known services"
  }

  assert {
    condition     = local.published_strings["tracing"] == jsonencode(sort(tolist(var.tracing)))
    error_message = "The published tracing list must follow the tfvars"
  }
}

run "tfvars_agent_access_names_known_services" {
  command = plan

  assert {
    condition     = alltrue([for s in keys(var.agent_access) : contains(["api", "worker"], s)])
    error_message = "agent_access in tfvars must be keyed by known services"
  }

  assert {
    condition     = local.published_strings["agent_access"] == jsonencode(var.agent_access)
    error_message = "The published agent_access must follow the tfvars"
  }
}
