# iam-app decides what each service may call in the agent stack (and grants it); this stack only injects the ids of
# those resources. Everything below is inert while agent_access is empty.
locals {
  agent_access = jsondecode(module.in.strings["agent_access"])
  agent_on     = length(local.agent_access) > 0

  agent_runtimes_used = distinct(flatten([for a in values(local.agent_access) : a.runtimes]))

  # Only read when a service calls the agent stack, so a project without AgentCore needs none of these keys.
  ssm_agent_strings = local.agent_on ? merge(
    {
      models              = "agent/models"
      guardrails          = "agent/guardrails"
      knowledge_bases     = "agent/knowledge_bases"
      bedrock_invoke      = "agent/bedrock_invoke"
      nat                 = "network/nat"
      interface_endpoints = "network/interface_endpoints"
    },
    { for r in local.agent_runtimes_used : "agent_runtime_${replace(r, "-", "_")}" => "agent/agent_runtime_${replace(r, "-", "_")}" },
  ) : {}
}

module "in_agent" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_agent_strings
}

locals {
  agent_models          = local.agent_on ? jsondecode(module.in_agent.strings["models"]) : {}
  agent_guardrails      = local.agent_on ? jsondecode(module.in_agent.strings["guardrails"]) : {}
  agent_knowledge_bases = local.agent_on ? jsondecode(module.in_agent.strings["knowledge_bases"]) : {}
  bedrock_invoke        = local.agent_on ? jsondecode(module.in_agent.strings["bedrock_invoke"]) : { enabled = false }
  agent_nat_mode        = local.agent_on ? jsondecode(module.in_agent.strings["nat"]).mode : null
  agent_endpoints       = local.agent_on ? toset(jsondecode(module.in_agent.strings["interface_endpoints"])) : toset([])

  # The same names as in the Runtime environment of the agent stack: the key in upper case, hyphens as underscores.
  # A service that is not listed gets empty lists and therefore no variable.
  agent_grants = {
    for s in keys(var.services) : s => {
      runtimes        = try(local.agent_access[s].runtimes, [])
      models          = try(local.agent_access[s].models, [])
      guardrails      = try(local.agent_access[s].guardrails, [])
      knowledge_bases = try(local.agent_access[s].knowledge_bases, [])
    }
  }

  agent_environment = {
    for s, a in local.agent_grants : s => merge(
      { for r in a.runtimes : "AGENTCORE_RUNTIME_ARN_${upper(replace(r, "-", "_"))}" => jsondecode(module.in_agent.strings["agent_runtime_${replace(r, "-", "_")}"]).arn },
      { for m in a.models : "MODEL_ID_${upper(replace(m, "-", "_"))}" => local.agent_models[m].model_id },
      { for g in a.guardrails : "GUARDRAIL_ID_${upper(replace(g, "-", "_"))}" => local.agent_guardrails[g].id },
      { for g in slice(a.guardrails, 0, min(length(a.guardrails), 1)) : "GUARDRAIL_VERSION" => "DRAFT" },
      { for k in a.knowledge_bases : "KNOWLEDGE_BASE_ID_${upper(replace(k, "-", "_"))}" => local.agent_knowledge_bases[k].id },
      { for m in slice(a.models, 0, local.bedrock_invoke.enabled ? min(length(a.models), 1) : 0) : "BEDROCK_INVOKE_ROLE_ARN" => local.bedrock_invoke.role_arn },
      { for m in slice(a.models, 0, local.bedrock_invoke.enabled ? min(length(a.models), 1) : 0) : "BEDROCK_INVOKE_SESSION_SECONDS" => tostring(local.bedrock_invoke.session_seconds) },
    )
  }

  # nat_mode external is a customer-managed VPC whose NAT is the customer's to provide, so it is not checked.
  agent_required_endpoints = toset(concat(
    anytrue([for a in values(local.agent_access) : length(a.runtimes) > 0]) ? ["bedrock-agentcore"] : [],
    anytrue([for a in values(local.agent_access) : length(a.models) + length(a.guardrails) > 0]) ? ["bedrock-runtime"] : [],
    anytrue([for a in values(local.agent_access) : length(a.knowledge_bases) > 0]) ? ["bedrock-agent-runtime"] : [],
    local.bedrock_invoke.enabled && anytrue([for a in values(local.agent_access) : length(a.models) > 0]) ? ["sts"] : [],
  ))
  agent_missing_endpoints = local.agent_nat_mode == "none" ? setsubtract(local.agent_required_endpoints, local.agent_endpoints) : toset([])
}
