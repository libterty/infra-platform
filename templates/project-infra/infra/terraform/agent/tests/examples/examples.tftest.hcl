# Run by scripts/validate.sh once per file in envs/examples/ with -var-file, so the examples cannot rot.
# Assertions hold for any valid example; do not set variables here, they would hide the example values.
mock_provider "aws" {}

# Every example configures the Runtime "assistant".
override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
  values = { insecure_value = "[\"assistant\"]" }
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

run "example_creates_the_runtimes" {
  command = plan

  assert {
    condition     = length(module.runtime) == length(var.agent_runtimes) && length(module.runtime_log_group) == length(var.agent_runtimes)
    error_message = "Every Runtime of the example must be created with its log group"
  }

  assert {
    condition     = alltrue([for r, cfg in var.agent_runtimes : local.runtime_inputs[r].network.mode == cfg.network_mode])
    error_message = "Every Runtime must run in the network mode the example names"
  }
}

run "example_keeps_message_content_out_of_traces" {
  command = plan

  assert {
    condition     = alltrue([for r, cfg in var.agent_runtimes : local.runtime_environment[r]["TRACELOOP_TRACE_CONTENT"] == lookup(cfg.environment, "TRACELOOP_TRACE_CONTENT", "false")])
    error_message = "TRACELOOP_TRACE_CONTENT must be false unless the example writes it out"
  }

  assert {
    condition     = alltrue([for r, cfg in var.agent_runtimes : contains(keys(local.log_delivery.sources), "${r}-traces") == cfg.tracing])
    error_message = "Traces must be delivered exactly for the Runtimes with tracing"
  }
}

run "example_models_never_pin_the_foundation_model_region" {
  command = plan

  assert {
    condition     = alltrue([for k, m in var.models : contains(local.model_base[k].invoke_arns, "arn:aws:bedrock:*::foundation-model/${m.foundation_model_id}")])
    error_message = "Every model must be allowed on its foundation model in any region"
  }
}

run "example_corpus_buckets_never_expire" {
  command = plan

  assert {
    condition     = length(module.corpus_bucket) == length(var.knowledge_bases) && alltrue([for b in values(local.corpus_buckets) : b.never_expire && b.kms_key_arn == null])
    error_message = "Every knowledge base of the example must get a corpus bucket that never expires"
  }
}
