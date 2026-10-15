# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what containerimage, network, iam-base and data publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/nat"]
  values = { insecure_value = "{\"mode\":\"single\",\"ids\":[\"nat-0123456789abcdef0\"]}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
  values = { insecure_value = "{}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/agent_service_roles"]
  values = { insecure_value = "[\"gateway\",\"knowledge_base\"]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/database"]
  values = { insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"app_endpoint\":\"alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com\",\"app_reader_endpoint\":\"alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com\",\"has_reader\":false,\"cluster_arn\":\"arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db\",\"data_api\":true}" }
}

# Values for the Runtime "assistant"; read only by the runs that configure it.
override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_assistant_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-agent-assistant" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agent_assistant_execution_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["network/sg_agent_assistant_id"]
  values = { insecure_value = "sg-0aaaaaaaaaaaaaaa1" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_bedrock_kb_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-bedrock-kb" }
}

override_data {
  target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agentcore_gateway_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agentcore-gateway" }
}

run "tfvars_create_what_they_list" {
  command = plan

  assert {
    condition = (
      length(module.runtime) == length(var.agent_runtimes) && length(module.memory) == length(var.memories) &&
      length(module.guardrail) == length(var.guardrails) && length(module.corpus_bucket) == length(var.knowledge_bases) &&
      length(module.gateway) == (var.agentcore_gateway == null ? 0 : 1)
    )
    error_message = "Every Runtime, Memory, guardrail, knowledge base and gateway in tfvars must be created, and nothing else"
  }

  assert {
    condition     = alltrue([for k in ["models", "guardrails", "agent_memories", "knowledge_bases", "agentcore_gateway", "bedrock_invoke"] : can(jsondecode(local.published_strings[k]))])
    error_message = "The agent keys must always be published as JSON, also when the tfvars turn nothing on"
  }
}
