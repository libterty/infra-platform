locals {
  ssm_input_strings = {
    kms_key_arn        = "foundation/kms_key_arn"
    data_access        = "network/data_access"
    role_rds_proxy_arn = "iam-base/role_rds_proxy_arn"
    database           = "data/database"
    # Lists and JSON published by the stacks of the AgentCore addendum; each is empty JSON when nothing is used.
    agent_runtimes    = "containerimage/agent_runtimes"
    agent_data_access = "network/agent_data_access"
    models            = "agent/models"
    guardrails        = "agent/guardrails"
    agent_memories    = "agent/agent_memories"
    knowledge_bases   = "agent/knowledge_bases"
    agentcore_gateway = "agent/agentcore_gateway"
    bedrock_invoke    = "agent/bedrock_invoke"
  }
  ssm_input_lists = {
    services = "containerimage/services"
  }
}

module "in" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
  lists      = local.ssm_input_lists
}

# Per-Runtime keys follow the Runtime list, and the service role ARNs exist only when iam-base created the role, so they
# need a second read. It reads nothing while the agent stack is empty.
locals {
  agent_runtime_names = jsondecode(module.in.strings["agent_runtimes"])
  agent_key           = { for r in local.agent_runtime_names : r => replace(r, "-", "_") }

  agent_models          = jsondecode(module.in.strings["models"])
  agent_guardrails      = jsondecode(module.in.strings["guardrails"])
  agent_memories        = jsondecode(module.in.strings["agent_memories"])
  agent_knowledge_bases = jsondecode(module.in.strings["knowledge_bases"])
  agent_gateway         = jsondecode(module.in.strings["agentcore_gateway"])
  bedrock_invoke        = jsondecode(module.in.strings["bedrock_invoke"])

  gateway_lambda_arns      = local.agent_gateway.enabled ? local.agent_gateway.lambda_arns : []
  gateway_tool_schema_arns = local.agent_gateway.enabled ? try(local.agent_gateway.tool_schema_arns, []) : []

  ssm_agent_strings = merge(
    { for r, k in local.agent_key : "agent_runtime_${k}" => "agent/agent_runtime_${k}" },
    { for r, k in local.agent_key : "role_agent_${k}_execution_arn" => "iam-base/role_agent_${k}_execution_arn" },
    length(local.agent_knowledge_bases) > 0 ? { role_bedrock_kb_arn = "iam-base/role_bedrock_kb_arn" } : {},
    length(local.gateway_lambda_arns) > 0 ? { role_agentcore_gateway_arn = "iam-base/role_agentcore_gateway_arn" } : {},
  )
}

module "in_agents" {
  source = "../../../../../modules/ssm-read" # After copying out of this repo, change to git::...?ref=ssm-read-v<semver>

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_agent_strings
}
