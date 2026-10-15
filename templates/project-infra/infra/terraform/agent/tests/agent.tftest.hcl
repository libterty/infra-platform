mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"
}

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

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      agent_runtimes      = "containerimage/agent_runtimes"
      nat                 = "network/nat"
      interface_endpoints = "network/interface_endpoints"
      agent_data_access   = "network/agent_data_access"
      agent_service_roles = "iam-base/agent_service_roles"
      database            = "data/database"
    } && local.ssm_input_lists == {}
    error_message = "agent must read the Runtime list, the NAT and endpoint decisions, the Runtime data access, the service role list and the database"
  }

  assert {
    condition     = local.ssm_agent_strings == {} && local.ssm_agent_lists == {}
    error_message = "Without Runtimes, knowledge bases or a gateway the second read must be empty"
  }
}

run "reads_runtime_keys" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition = local.ssm_agent_strings == {
      ecr_agent_assistant_url            = "containerimage/ecr_agent_assistant_url"
      role_agent_assistant_execution_arn = "iam-base/role_agent_assistant_execution_arn"
      sg_agent_assistant_id              = "network/sg_agent_assistant_id"
    } && local.ssm_agent_lists == { subnet_ids_app = "network/subnet_ids_app" }
    error_message = "A VPC Runtime must read its repository, execution role, security group and the subnets of its tier"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      models            = "/alpha/dev/agent/models"
      guardrails        = "/alpha/dev/agent/guardrails"
      agent_memories    = "/alpha/dev/agent/agent_memories"
      knowledge_bases   = "/alpha/dev/agent/knowledge_bases"
      agentcore_gateway = "/alpha/dev/agent/agentcore_gateway"
      bedrock_invoke    = "/alpha/dev/agent/bedrock_invoke"
    }
    error_message = "ssm-publish must write the agent keys under the agent stack path, also when they are empty"
  }
}

run "nothing_by_default" {
  command = plan

  assert {
    condition = (
      length(module.guardrail) == 0 && length(module.inference_profile) == 0 && length(module.memory) == 0 &&
      length(module.runtime) == 0 && length(module.runtime_log_group) == 0 && length(module.runtime_logs) == 0 &&
      length(module.gateway) == 0 && length(module.knowledge_base) == 0 && length(module.corpus_bucket) == 0
    )
    error_message = "With every input at its default the agent stack must create nothing"
  }

  assert {
    condition = (
      local.published_strings["models"] == "{}" && local.published_strings["guardrails"] == "{}" &&
      local.published_strings["agent_memories"] == "{}" && local.published_strings["knowledge_bases"] == "{}" &&
      local.published_strings["agentcore_gateway"] == "{\"enabled\":false}" && local.published_strings["bedrock_invoke"] == "{\"enabled\":false}"
    )
    error_message = "With every input at its default the published JSON must be empty"
  }
}

run "publishes_agent_keys" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" }, order-bot = { image_tag = "abc1234", network_mode = "PUBLIC" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\",\"order-bot\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["containerimage/ecr_agent_order_bot_url"]
    values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-agent-order-bot" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["iam-base/role_agent_order_bot_execution_arn"]
    values = { insecure_value = "arn:aws:iam::111111111111:role/alpha-dev-agent-order-bot" }
  }

  assert {
    condition = toset(keys(module.ssm_publish.names)) == toset([
      "models", "guardrails", "agent_memories", "knowledge_bases", "agentcore_gateway", "bedrock_invoke",
      "agent_runtime_assistant", "agent_runtime_order_bot",
    ])
    error_message = "agent must publish the project keys and one agent_runtime_<name> per Runtime"
  }
}

run "runtime_json_shape" {
  command = plan

  variables {
    agent_runtimes = {
      assistant = { image_tag = "abc1234", models = ["chat"], guardrails = ["safety"], tracing = true }
    }
    models = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0" } }
    guardrails = {
      safety = {
        blocked_input_message   = "blocked"
        blocked_output_message  = "blocked"
        cross_region_profile_id = "apac.guardrail.v1:0"
        content_filters         = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_module {
    target = module.runtime["assistant"]
    outputs = {
      runtime_arn  = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj"
      runtime_id   = "alpha_dev_assistant-AbCdEfGhIj"
      runtime_name = "alpha_dev_assistant"
    }
  }

  assert {
    condition = jsondecode(local.published_strings["agent_runtime_assistant"]) == {
      arn                = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_assistant-AbCdEfGhIj"
      id                 = "alpha_dev_assistant-AbCdEfGhIj"
      name               = "alpha_dev_assistant"
      execution_role_arn = "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant"
      models             = ["chat"]
      memories           = []
      guardrails         = ["safety"]
      knowledge_bases    = []
      gateway            = false
      tracing            = true
    }
    error_message = "agent_runtime_<name> must carry the Runtime ids, its execution role and the keys it may use"
  }
}

# ---- Runtime wiring ----

run "runtime_wired_from_upstream" {
  command = plan

  variables {
    agent_runtimes = {
      assistant = { image_tag = "abc1234", session_lifecycle = { idle_session_timeout = 600 } }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition = jsonencode(local.runtime_inputs["assistant"]) == jsonencode({
      name          = "alpha_dev_assistant"
      role_arn      = "arn:aws:iam::111111111111:role/alpha-dev-agent-assistant"
      container_uri = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/alpha-dev-agent-assistant:abc1234"
      network = {
        mode               = "VPC"
        subnet_ids         = ["subnet-0app1", "subnet-0app2"]
        security_group_ids = ["sg-0aaaaaaaaaaaaaaa1"]
      }
    })
    error_message = "The Runtime must be named <project>_<env>_<name> and take its role, image, subnets and security group from SSM"
  }

  assert {
    condition     = module.runtime_log_group["assistant"].name == "/agentcore/alpha-dev-assistant"
    error_message = "Each Runtime must get the application log group /agentcore/<project>-<env>-<name>"
  }
}

run "public_runtime_is_explicit" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", network_mode = "PUBLIC" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = jsonencode(local.runtime_inputs["assistant"].network) == jsonencode({ mode = "PUBLIC", subnet_ids = [], security_group_ids = [] })
    error_message = "A PUBLIC Runtime must not get subnets or security groups"
  }

  assert {
    condition     = !contains(keys(local.ssm_agent_strings), "sg_agent_assistant_id") && local.ssm_agent_lists == {}
    error_message = "A PUBLIC Runtime must not read a security group or subnets"
  }
}

run "runtime_defaults_to_vpc" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = var.agent_runtimes["assistant"].network_mode == "VPC" && local.runtime_inputs["assistant"].network.mode == "VPC"
    error_message = "A Runtime must run in the VPC unless PUBLIC is written out"
  }
}

run "runtime_image_tag_latest_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "latest" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_network_mode_unknown_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", network_mode = "PRIVATE" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_public_tier_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", subnet_tier = "public" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_other_tier_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", subnet_tier = "agent" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in_agents.data.aws_ssm_parameter.this["network/subnet_ids_agent"]
    values = { insecure_value = "subnet-0agt1,subnet-0agt2" }
  }

  assert {
    condition     = jsonencode(local.runtime_inputs["assistant"].network.subnet_ids) == jsonencode(["subnet-0agt1", "subnet-0agt2"])
    error_message = "A Runtime must use the subnets of the tier it names"
  }
}

run "runtimes_must_match_containerimage_extra_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  expect_failures = [terraform_data.agent_runtimes_match_containerimage]
}

run "runtimes_must_match_containerimage_missing_rejected" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [terraform_data.agent_runtimes_match_containerimage]
}

run "runtime_references_unknown_model_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", models = ["chat"] } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_gateway_without_gateway_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", gateway = true } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

# ---- Runtime environment ----

run "runtime_env_only_from_ssm_and_stack" {
  command = plan

  variables {
    agent_runtimes = {
      assistant = {
        image_tag   = "abc1234"
        models      = ["chat"]
        memories    = ["conversation"]
        guardrails  = ["safety"]
        environment = { APP_MODE = "chat" }
      }
    }
    models   = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "apac" } }
    memories = { conversation = {} }
    guardrails = {
      safety = {
        blocked_input_message   = "blocked"
        blocked_output_message  = "blocked"
        cross_region_profile_id = "apac.guardrail.v1:0"
        content_filters         = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  override_module {
    target  = module.memory["conversation"]
    outputs = { memory_id = "alpha_dev_conversation-AbCdEfGhIj", memory_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_conversation-AbCdEfGhIj" }
  }

  override_module {
    target  = module.guardrail["safety"]
    outputs = { guardrail_id = "abcdefgh1234", guardrail_arn = "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234", version = "DRAFT", cross_region_profile_id = "apac.guardrail.v1:0" }
  }

  assert {
    condition = local.runtime_environment["assistant"] == {
      AWS_REGION              = "ap-northeast-1"
      TRACELOOP_TRACE_CONTENT = "false"
      MODEL_ID_CHAT           = "apac.anthropic.claude-sonnet-4-5-20250929-v1:0"
      MEMORY_ID_CONVERSATION  = "alpha_dev_conversation-AbCdEfGhIj"
      GUARDRAIL_ID_SAFETY     = "abcdefgh1234"
      GUARDRAIL_VERSION       = "DRAFT"
      DB_HOST                 = "alpha-dev-db.cluster-abc.ap-northeast-1.rds.amazonaws.com"
      DB_READER_HOST          = "alpha-dev-db.cluster-ro-abc.ap-northeast-1.rds.amazonaws.com"
      DB_PORT                 = "5432"
      DB_NAME                 = "app"
      DB_SECRET_ARN           = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"
      APP_MODE                = "chat"
    }
    error_message = "The Runtime environment must be exactly the template variables built from SSM and this stack, plus the project's own"
  }
}

run "runtime_env_without_data_access_has_no_db" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = local.runtime_environment["assistant"] == { AWS_REGION = "ap-northeast-1", TRACELOOP_TRACE_CONTENT = "false" }
    error_message = "A Runtime that is not in agent_data_access must get no DB_* variable"
  }
}

run "runtime_env_trace_content_override" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", environment = { TRACELOOP_TRACE_CONTENT = "true" } } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = local.runtime_environment["assistant"]["TRACELOOP_TRACE_CONTENT"] == "true"
    error_message = "environment must be able to turn TRACELOOP_TRACE_CONTENT on"
  }
}

run "runtime_env_template_name_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", environment = { MODEL_ID_X = "some-model" } } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_env_db_name_rejected" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", environment = { DB_HOST = "elsewhere" } } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  expect_failures = [var.agent_runtimes]
}

run "runtime_tracing_env_and_delivery" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", tracing = true } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition = (
      local.runtime_environment["assistant"]["OTEL_TRACES_EXPORTER"] == "otlp" &&
      local.runtime_environment["assistant"]["OTEL_EXPORTER_OTLP_PROTOCOL"] == "http/protobuf" &&
      local.runtime_environment["assistant"]["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] == "https://xray.ap-northeast-1.amazonaws.com/v1/traces" &&
      local.runtime_environment["assistant"]["OTEL_SERVICE_NAME"] == "alpha-dev-assistant" &&
      local.runtime_environment["assistant"]["TRACELOOP_TRACE_CONTENT"] == "false"
    )
    error_message = "A traced Runtime must export OTLP over http/protobuf to X-Ray and still keep message content out of traces"
  }

  assert {
    condition = (
      toset(keys(local.log_delivery.sources)) == toset(["assistant-logs", "assistant-traces"]) &&
      local.log_delivery.sources["assistant-traces"].log_type == "TRACES" &&
      local.log_delivery.destinations["xray_traces"] == { type = "XRAY", resource_arn = null } &&
      local.log_delivery.deliveries["assistant-traces"] == { source = "assistant-traces", destination = "xray_traces" } &&
      local.log_delivery.deliveries["assistant-logs"] == { source = "assistant-logs", destination = "assistant" }
    )
    error_message = "A traced Runtime must deliver its application logs to its log group and its traces to X-Ray"
  }
}

run "runtime_untraced_has_logs_only" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = keys(local.log_delivery.sources) == ["assistant-logs"] && keys(local.log_delivery.destinations) == ["assistant"] && length(module.runtime_logs) == 1
    error_message = "A Runtime without tracing must deliver only its application logs, and no X-Ray destination may exist"
  }

  assert {
    condition     = length([for k in keys(local.runtime_environment["assistant"]) : k if startswith(k, "OTEL_")]) == 0
    error_message = "A Runtime without tracing must get no OTEL variable"
  }
}

# ---- Models ----

run "invoke_arns_shapes" {
  command = plan

  variables {
    models = {
      on-demand = { foundation_model_id = "anthropic.claude-haiku-4-5-20251001-v1:0" }
      regional  = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "apac" }
      global    = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "global" }
      tracked   = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "apac", tracked = true }
    }
  }

  override_module {
    target = module.inference_profile[0]
    outputs = {
      arns = { tracked = "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/abcd1234" }
      ids  = { tracked = "abcd1234" }
    }
  }

  assert {
    condition     = local.models["on-demand"] == { model_id = "anthropic.claude-haiku-4-5-20251001-v1:0", invoke_arns = ["arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"] }
    error_message = "A model without a prefix is called by its id and allowed on the foundation model in any region"
  }

  assert {
    condition = local.models["regional"] == {
      model_id = "apac.anthropic.claude-sonnet-4-5-20250929-v1:0"
      invoke_arns = [
        "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
      ]
    }
    error_message = "A model with a prefix is called through the system inference profile and allowed on the profile and on the foundation model in any region"
  }

  assert {
    condition = local.models["global"].invoke_arns == [
      "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0",
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
      "arn:aws:bedrock:::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
    ]
    error_message = "A global profile also needs the foundation model ARN with an empty region and account"
  }

  assert {
    condition = local.models["tracked"] == {
      model_id = "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/abcd1234"
      invoke_arns = [
        "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
        "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/abcd1234",
      ]
    }
    error_message = "A tracked model is called through its application inference profile, which is added to the ARNs of its source"
  }

  assert {
    condition     = alltrue(flatten([for m in values(local.models) : [for a in m.invoke_arns : !startswith(a, "arn:aws:bedrock:ap-northeast-1::foundation-model/")]]))
    error_message = "The foundation-model ARN must never be pinned to one region"
  }

  assert {
    condition     = local.tracked_models == { tracked = { copy_from = "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-sonnet-4-5-20250929-v1:0" } }
    error_message = "Only tracked models get an application inference profile, copied from their system profile"
  }

  assert {
    condition     = local.published_strings["models"] == jsonencode(local.models) && length(jsondecode(local.published_strings["models"])) == 4
    error_message = "The models JSON must publish the model id and invoke ARNs"
  }
}

run "tracked_on_demand_model_copies_the_foundation_model" {
  command = plan

  variables {
    models = { tracked = { foundation_model_id = "anthropic.claude-haiku-4-5-20251001-v1:0", tracked = true } }
  }

  assert {
    condition     = local.tracked_models["tracked"].copy_from == "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"
    error_message = "A tracked model without a prefix copies the foundation model of this region"
  }
}

run "model_id_with_region_prefix_rejected" {
  command = plan

  variables {
    models = { chat = { foundation_model_id = "anthropic claude" } }
  }

  expect_failures = [var.models]
}

# ---- Guardrails and Memories ----

run "guardrail_defaults_standard" {
  command = plan

  variables {
    guardrails = {
      safety = {
        blocked_input_message   = "blocked"
        blocked_output_message  = "blocked"
        cross_region_profile_id = "apac.guardrail.v1:0"
        content_filters         = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
    }
  }

  assert {
    condition     = var.guardrails["safety"].tier == "STANDARD" && module.guardrail["safety"].name == "alpha-dev-safety"
    error_message = "A guardrail must default to STANDARD and be named <project>-<env>-<key>"
  }

  assert {
    condition     = module.guardrail["safety"].version == "DRAFT" && module.guardrail["safety"].cross_region_profile_id == "apac.guardrail.v1:0"
    error_message = "The guardrail must be used at DRAFT with its cross-region profile"
  }
}

run "guardrails_json" {
  command = plan

  variables {
    guardrails = {
      safety = {
        blocked_input_message   = "blocked"
        blocked_output_message  = "blocked"
        cross_region_profile_id = "apac.guardrail.v1:0"
        content_filters         = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
      english = {
        blocked_input_message  = "blocked"
        blocked_output_message = "blocked"
        tier                   = "CLASSIC"
        content_filters        = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
    }
  }

  override_module {
    target  = module.guardrail["safety"]
    outputs = { guardrail_id = "abcdefgh1234", guardrail_arn = "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234", version = "DRAFT", cross_region_profile_id = "apac.guardrail.v1:0" }
  }

  override_module {
    target  = module.guardrail["english"]
    outputs = { guardrail_id = "ijklmnop5678", guardrail_arn = "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678", version = "DRAFT", cross_region_profile_id = null }
  }

  assert {
    condition = jsondecode(local.published_strings["guardrails"]) == {
      safety  = { id = "abcdefgh1234", arn = "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/abcdefgh1234", version = "DRAFT", profile_id = "apac.guardrail.v1:0" }
      english = { id = "ijklmnop5678", arn = "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail/ijklmnop5678", version = "DRAFT", profile_id = null }
    }
    error_message = "The guardrails JSON must carry id, ARN, DRAFT and the profile id, which is null for CLASSIC"
  }
}

run "memory_named_and_published" {
  command = plan

  variables {
    memories = { chat-history = { event_expiry_days = 7 } }
  }

  override_module {
    target  = module.memory["chat-history"]
    outputs = { memory_id = "alpha_dev_chat_history-AbCdEfGhIj", memory_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_chat_history-AbCdEfGhIj" }
  }

  assert {
    condition     = jsondecode(local.published_strings["agent_memories"]) == { chat-history = { id = "alpha_dev_chat_history-AbCdEfGhIj", arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_chat_history-AbCdEfGhIj" } }
    error_message = "The memories JSON must carry the Memory id and ARN"
  }
}

run "memory_expiry_below_seven_rejected" {
  command = plan

  variables {
    memories = { conversation = { event_expiry_days = 6 } }
  }

  expect_failures = [var.memories]
}

run "memory_expiry_above_365_rejected" {
  command = plan

  variables {
    memories = { conversation = { event_expiry_days = 366 } }
  }

  expect_failures = [var.memories]
}

run "memory_expiry_at_365_passes" {
  command = plan

  variables {
    memories = { conversation = { event_expiry_days = 365 } }
  }

  assert {
    condition     = length(module.memory) == 1
    error_message = "event_expiry_days 365 must pass"
  }
}

# ---- Networking without a NAT ----

run "nat_none_requires_bedrock_runtime" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_requires_bedrock_agentcore" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_with_endpoints_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  assert {
    condition     = length(local.agent_missing_endpoints) == 0
    error_message = "bedrock-runtime and bedrock-agentcore are enough for a plain VPC Runtime without a NAT"
  }
}

run "nat_external_is_not_checked" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", tracing = true } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"external\",\"ids\":[]}" }
  }

  assert {
    condition     = length(local.agent_missing_endpoints) == 0
    error_message = "The NAT of a customer VPC is the customer's to provide"
  }
}

run "nat_none_public_runtime_is_not_checked" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", network_mode = "PUBLIC" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  assert {
    condition     = length(local.agent_missing_endpoints) == 0
    error_message = "A PUBLIC Runtime does not use the VPC endpoints"
  }
}

run "nat_none_tracing_requires_xray" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", tracing = true } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_cross_account_requires_sts" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", models = ["chat"] } }
    models         = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0" } }
    bedrock_invoke = { role_arn = "arn:aws:iam::333333333333:role/bedrock-invoke" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_knowledge_base_requires_agent_runtime_endpoint" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", knowledge_bases = ["products"] } }
    models         = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_db_runtime_requires_secretsmanager" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_endpoints_exist]
}

run "nat_none_db_runtime_with_secretsmanager_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\",\"secretsmanager\"]" }
  }

  assert {
    condition     = length(local.agent_missing_endpoints) == 0
    error_message = "A VPC Runtime that reads the database secret needs only the secretsmanager endpoint on top of the base set"
  }
}

run "kb_secret_wildcard_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:*"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_secret_without_suffix_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "nat_none_blocks_gateway" {
  command = plan

  variables {
    agent_runtimes    = { assistant = { image_tag = "abc1234", gateway = true } }
    agentcore_gateway = { targets = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/nat"]
    values = { insecure_value = "{\"mode\":\"none\",\"ids\":[]}" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/interface_endpoints"]
    values = { insecure_value = "[\"bedrock-agentcore\",\"bedrock-runtime\"]" }
  }

  expect_failures = [terraform_data.no_nat_no_gateway]
}

run "gateway_with_nat_passes" {
  command = plan

  variables {
    agent_runtimes    = { assistant = { image_tag = "abc1234", gateway = true } }
    agentcore_gateway = { targets = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = length(module.gateway) == 1
    error_message = "With a NAT a VPC Runtime may use the gateway"
  }
}

# ---- Gateway ----

run "gateway_wiring_and_json" {
  command = plan

  variables {
    agentcore_gateway = {
      targets = {
        order-lookup = {
          type               = "lambda"
          lambda_arn         = "arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup"
          tool_schema_s3_uri = "s3://alpha-dev-tools/order-lookup.json"
        }
        docs = { type = "mcp_server", endpoint = "https://mcp.example.com/mcp" }
      }
    }
  }

  override_module {
    target = module.gateway["this"]
    outputs = {
      gateway_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij"
      gateway_url = "https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp"
    }
  }

  assert {
    condition = jsondecode(local.published_strings["agentcore_gateway"]) == {
      enabled          = true
      arn              = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:gateway/alpha-dev-gateway-abcdefghij"
      url              = "https://alpha-dev-gateway-abcdefghij.gateway.bedrock-agentcore.ap-northeast-1.amazonaws.com/mcp"
      lambda_arns      = ["arn:aws:lambda:ap-northeast-1:111111111111:function:alpha-dev-order-lookup"]
      tool_schema_arns = ["arn:aws:s3:::alpha-dev-tools/order-lookup.json"]
    }
    error_message = "The gateway JSON must carry the ARN, the URL, the Lambda target ARNs and the exact tool schema object ARNs only"
  }

  assert {
    condition     = local.ssm_agent_strings["role_agentcore_gateway_arn"] == "iam-base/role_agentcore_gateway_arn"
    error_message = "The gateway role must come from iam-base"
  }
}

run "gateway_needs_its_service_role" {
  command = plan

  variables {
    agentcore_gateway = { targets = {} }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["iam-base/agent_service_roles"]
    values = { insecure_value = "[\"knowledge_base\"]" }
  }

  expect_failures = [terraform_data.service_roles_exist]
}

# ---- Knowledge bases ----

run "kb_corpus_bucket" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources = {
          manuals = { inclusion_prefixes = ["manuals/"] }
          faq     = {}
        }
      }
      policies = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-policies-AbCdEf"
        data_sources           = { all = {} }
      }
    }
  }

  override_module {
    target  = module.corpus_bucket["products"]
    outputs = { bucket_name = "alpha-dev-kb-products-111111111111", arn = "arn:aws:s3:::alpha-dev-kb-products-111111111111" }
  }

  override_module {
    target  = module.corpus_bucket["policies"]
    outputs = { bucket_name = "alpha-dev-kb-policies-111111111111", arn = "arn:aws:s3:::alpha-dev-kb-policies-111111111111" }
  }

  assert {
    condition     = toset(keys(module.corpus_bucket)) == toset(["products", "policies"])
    error_message = "Each knowledge base must get its own corpus bucket"
  }

  assert {
    condition = local.corpus_buckets["products"] == {
      name          = "alpha-dev-kb-products-111111111111"
      kms_key_arn   = null
      never_expire  = true
      log_delivery  = []
      force_destroy = false
    }
    error_message = "The corpus bucket must be <project>-<env>-kb-<key>-<account>, never expire, use SSE-S3, take no log delivery and refuse force_destroy"
  }

  assert {
    condition = (
      jsonencode(local.knowledge_base_inputs["products"].data_sources) == jsonencode({
        manuals = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-products-111111111111", inclusion_prefixes = ["manuals/"] }
        faq     = { bucket_arn = "arn:aws:s3:::alpha-dev-kb-products-111111111111", inclusion_prefixes = [] }
      }) &&
      local.knowledge_base_inputs["policies"].data_sources["all"].bucket_arn == "arn:aws:s3:::alpha-dev-kb-policies-111111111111"
    )
    error_message = "Every data source of a knowledge base must read the corpus bucket of that same knowledge base"
  }

  assert {
    condition = jsonencode(local.knowledge_base_inputs["products"].aurora) == jsonencode({
      cluster_arn            = "arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db"
      credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
      database_name          = "app"
      table_name             = "bedrock_integration.bedrock_kb"
      field_mapping          = { primary_key_field = "id", vector_field = "embedding", text_field = "chunks", metadata_field = "metadata", custom_metadata_field = null }
    })
    error_message = "The knowledge base must use the cluster and database of the data stack and its own secret"
  }

  assert {
    condition     = local.knowledge_base_inputs["products"].embedding_model_arn == "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0" && local.knowledge_base_inputs["products"].name == "alpha-dev-products"
    error_message = "The knowledge base must be named <project>-<env>-<key> and embed with the foundation model of this region"
  }
}

run "kb_corpus_bucket_name_too_long" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      # alpha-dev-kb- (13) + 38 + -111111111111 (13) = 64 characters.
      abcdefghijabcdefghijabcdefghijabcdefgh = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-AbCdEf"
        data_sources           = { all = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_corpus_bucket_name_at_limit_passes" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      abcdefghijabcdefghijabcdefghijabcdefg = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-AbCdEf"
        data_sources           = { all = {} }
      }
    }
  }

  assert {
    condition     = length("alpha-dev-kb-abcdefghijabcdefghijabcdefghijabcdefg-111111111111") == 63 && length(module.corpus_bucket) == 1
    error_message = "A corpus bucket name of exactly 63 characters must pass"
  }
}

run "kb_requires_aurora_data_api_rds_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"enabled\":true,\"deployment\":\"rds\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!db-0000-AbCdEf\",\"cluster_arn\":null,\"data_api\":false}" }
  }

  expect_failures = [terraform_data.knowledge_base_database]
}

run "kb_requires_aurora_data_api_off_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"enabled\":true,\"deployment\":\"aurora_serverless\",\"port\":5432,\"name\":\"app\",\"secret_arn\":\"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf\",\"cluster_arn\":\"arn:aws:rds:ap-northeast-1:111111111111:cluster:alpha-dev-db\",\"data_api\":false}" }
  }

  expect_failures = [terraform_data.knowledge_base_database]
}

run "kb_requires_a_database" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["data/database"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  expect_failures = [terraform_data.knowledge_base_database]
}

run "kb_requires_the_service_role" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["iam-base/agent_service_roles"]
    values = { insecure_value = "[\"gateway\"]" }
  }

  expect_failures = [terraform_data.service_roles_exist]
}

run "kb_ready_passes" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  assert {
    condition     = local.knowledge_base_database_ready && length(module.knowledge_base) == 1
    error_message = "An Aurora database with the Data API, the knowledge base role and a dedicated secret must pass"
  }
}

run "kb_embedding_model_with_prefix_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0", inference_profile_prefix = "apac" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_secret_not_master" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [terraform_data.knowledge_base_secret_is_not_master]
}

run "kb_secret_not_a_secret_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:ssm:ap-northeast-1:111111111111:parameter/alpha-dev/kb-products"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_secret_other_region_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_secret_other_account_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:222222222222:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

run "kb_dedicated_secret_passed_as_is" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  assert {
    condition     = local.knowledge_base_inputs["products"].aurora.credentials_secret_arn == "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
    error_message = "A dedicated secret must be passed to the module as it is"
  }
}

run "publishes_kb_bucket_and_secret" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      products = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources = {
          manuals = { inclusion_prefixes = ["manuals/", "faq/"] }
        }
      }
    }
  }

  override_module {
    target  = module.corpus_bucket["products"]
    outputs = { bucket_name = "alpha-dev-kb-products-111111111111", arn = "arn:aws:s3:::alpha-dev-kb-products-111111111111" }
  }

  override_module {
    target = module.knowledge_base["products"]
    outputs = {
      knowledge_base_id  = "KBID000001"
      knowledge_base_arn = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"
      data_source_ids    = { manuals = "DSID000001" }
    }
  }

  assert {
    condition = jsondecode(local.published_strings["knowledge_bases"]) == {
      products = {
        id                     = "KBID000001"
        arn                    = "arn:aws:bedrock:ap-northeast-1:111111111111:knowledge-base/KBID000001"
        embedding_model        = "embedding"
        bucket_name            = "alpha-dev-kb-products-111111111111"
        bucket_arn             = "arn:aws:s3:::alpha-dev-kb-products-111111111111"
        inclusion_prefixes     = { manuals = ["faq/", "manuals/"] }
        data_source_ids        = { manuals = "DSID000001" }
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
      }
    }
    error_message = "The knowledge base JSON must carry its ids, the corpus bucket, the prefixes and ids per data source and the dedicated secret"
  }
}

run "model_key_not_kebab_case_rejected" {
  command = plan

  variables {
    models = { chat_model = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0" } }
  }

  expect_failures = [var.models]
}

run "model_prefix_invalid_rejected" {
  command = plan

  variables {
    models = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", inference_profile_prefix = "apac." } }
  }

  expect_failures = [var.models]
}

run "guardrail_key_not_kebab_case_rejected" {
  command = plan

  variables {
    guardrails = {
      Safety = {
        blocked_input_message   = "blocked"
        blocked_output_message  = "blocked"
        cross_region_profile_id = "apac.guardrail.v1:0"
        content_filters         = { HATE = { input_strength = "HIGH", output_strength = "HIGH" } }
      }
    }
  }

  expect_failures = [var.guardrails]
}

run "memory_name_too_long_rejected" {
  command = plan

  variables {
    # alpha_dev_ is 10 characters, so 39 more make 49.
    memories = { abcdefghijabcdefghijabcdefghijabcdefghi = {} }
  }

  expect_failures = [var.memories]
}

run "knowledge_base_key_not_kebab_case_rejected" {
  command = plan

  variables {
    models = { embedding = { foundation_model_id = "amazon.titan-embed-text-v2:0" } }
    knowledge_bases = {
      product_docs = {
        embedding_model        = "embedding"
        embedding_dimensions   = 1024
        credentials_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/kb-products-AbCdEf"
        data_sources           = { manuals = {} }
      }
    }
  }

  expect_failures = [var.knowledge_bases]
}

# ---- Runtime placement and cross-account ----

run "public_runtime_without_db" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", network_mode = "PUBLIC" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  expect_failures = [terraform_data.public_runtime_without_data_access]
}

run "vpc_runtime_with_db_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234" } }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/agent_data_access"]
    values = { insecure_value = "{\"db\":[\"assistant\"]}" }
  }

  assert {
    condition     = local.runtime_environment["assistant"]["DB_NAME"] == "app"
    error_message = "A VPC Runtime in agent_data_access must get the database settings"
  }
}

run "cross_account_session_899_rejected" {
  command = plan

  variables {
    bedrock_invoke = { role_arn = "arn:aws:iam::333333333333:role/bedrock-invoke", session_seconds = 899 }
  }

  expect_failures = [var.bedrock_invoke]
}

run "cross_account_session_900_passes" {
  command = plan

  variables {
    agent_runtimes = { assistant = { image_tag = "abc1234", models = ["chat"] } }
    models         = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0" } }
    bedrock_invoke = { role_arn = "arn:aws:iam::333333333333:role/bedrock-invoke", session_seconds = 900 }
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["containerimage/agent_runtimes"]
    values = { insecure_value = "[\"assistant\"]" }
  }

  assert {
    condition     = jsondecode(local.published_strings["bedrock_invoke"]) == { enabled = true, role_arn = "arn:aws:iam::333333333333:role/bedrock-invoke", session_seconds = 900 }
    error_message = "The cross-account decision must be published with the role and the session length"
  }

  assert {
    condition = (
      local.runtime_environment["assistant"]["BEDROCK_INVOKE_ROLE_ARN"] == "arn:aws:iam::333333333333:role/bedrock-invoke" &&
      local.runtime_environment["assistant"]["BEDROCK_INVOKE_SESSION_SECONDS"] == "900"
    )
    error_message = "A Runtime that calls models must get the role to assume and the session length"
  }
}

run "cross_account_with_tracked_model_rejected" {
  command = plan

  variables {
    models         = { chat = { foundation_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0", tracked = true } }
    bedrock_invoke = { role_arn = "arn:aws:iam::333333333333:role/bedrock-invoke" }
  }

  expect_failures = [var.bedrock_invoke]
}

run "cross_account_role_in_this_account_rejected" {
  command = plan

  variables {
    bedrock_invoke = { role_arn = "arn:aws:iam::111111111111:role/bedrock-invoke" }
  }

  expect_failures = [var.bedrock_invoke]
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
