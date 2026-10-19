locals {
  # MODEL_ID_<KEY> and friends: the key in upper case with hyphens turned into underscores.
  env_key = { for k in distinct(concat(keys(var.models), keys(var.memories), keys(var.guardrails), keys(var.knowledge_bases))) : k => upper(replace(k, "-", "_")) }

  # Built here from the other stacks' SSM values, never from tfvars, so a rebuilt resource cannot leave a stale id behind.
  runtime_environment = {
    for r, cfg in var.agent_runtimes : r => merge(
      {
        AWS_REGION = var.aws_region
        # Message content stays out of traces unless the project writes "true" in environment.
        TRACELOOP_TRACE_CONTENT = "false"
      },
      { for m in cfg.models : "MODEL_ID_${local.env_key[m]}" => local.models[m].model_id },
      { for m in cfg.memories : "MEMORY_ID_${local.env_key[m]}" => module.memory[m].memory_id },
      { for g in cfg.guardrails : "GUARDRAIL_ID_${local.env_key[g]}" => module.guardrail[g].guardrail_id },
      length(cfg.guardrails) > 0 ? { GUARDRAIL_VERSION = "DRAFT" } : {},
      { for k in cfg.knowledge_bases : "KNOWLEDGE_BASE_ID_${local.env_key[k]}" => module.knowledge_base[k].knowledge_base_id },
      cfg.gateway ? { AGENTCORE_GATEWAY_URL = module.gateway["this"].gateway_url } : {},
      # The same names as the ECS services. The secret is read by the Runtime with its execution role, never injected.
      local.database.enabled && contains(local.db_runtimes, r) ? {
        DB_HOST        = local.database.app_endpoint
        DB_READER_HOST = local.database.app_reader_endpoint
        DB_PORT        = tostring(local.database.port)
        DB_NAME        = local.database.name
        DB_SECRET_ARN  = local.database.secret_arn
      } : {},
      var.bedrock_invoke != null && length(cfg.models) > 0 ? {
        BEDROCK_INVOKE_ROLE_ARN        = var.bedrock_invoke.role_arn
        BEDROCK_INVOKE_SESSION_SECONDS = tostring(var.bedrock_invoke.session_seconds)
      } : {},
      cfg.tracing ? {
        OTEL_SERVICE_NAME                  = "${local.name_prefix}-${r}"
        OTEL_TRACES_EXPORTER               = "otlp"
        OTEL_EXPORTER_OTLP_PROTOCOL        = "http/protobuf"
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "https://xray.${var.aws_region}.amazonaws.com/v1/traces"
        OTEL_METRICS_EXPORTER              = "none"
        OTEL_LOGS_EXPORTER                 = "none"
      } : {},
      cfg.environment,
    )
  }

  runtime_inputs = {
    for r, cfg in var.agent_runtimes : r => {
      name          = replace("${local.name_prefix}-${r}", "-", "_")
      role_arn      = module.in_agents.strings["role_agent_${local.agent_key[r]}_execution_arn"]
      container_uri = "${module.in_agents.strings["ecr_agent_${local.agent_key[r]}_url"]}:${cfg.image_tag}"
      network = cfg.network_mode == "PUBLIC" ? { mode = "PUBLIC", subnet_ids = [], security_group_ids = [] } : {
        mode               = "VPC"
        subnet_ids         = module.in_agents.lists["subnet_ids_${cfg.subnet_tier}"]
        security_group_ids = [module.in_agents.strings["sg_agent_${local.agent_key[r]}_id"]]
      }
    }
  }
}

module "runtime" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/agentcore-runtime/aws"
  version  = "~> 0.1.0"
  for_each = var.agent_runtimes

  name                  = local.runtime_inputs[each.key].name
  role_arn              = local.runtime_inputs[each.key].role_arn
  container_uri         = local.runtime_inputs[each.key].container_uri
  network               = local.runtime_inputs[each.key].network
  session_lifecycle     = each.value.session_lifecycle
  protocol              = each.value.protocol
  environment_variables = local.runtime_environment[each.key]
}

module "runtime_log_group" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/log-group/aws"
  version  = "~> 0.1.0"
  for_each = var.agent_runtimes

  name           = "/agentcore/${local.name_prefix}-${each.key}"
  retention_days = each.value.log_retention_days
}

locals {
  # Runtime keys are kebab-case, so the XRAY destination key xray_traces cannot clash with them.
  log_delivery = {
    sources = merge(
      { for r in keys(var.agent_runtimes) : "${r}-logs" => { resource_arn = module.runtime[r].runtime_arn, log_type = "APPLICATION_LOGS" } },
      { for r, cfg in var.agent_runtimes : "${r}-traces" => { resource_arn = module.runtime[r].runtime_arn, log_type = "TRACES" } if cfg.tracing },
    )
    destinations = merge(
      { for r, lg in module.runtime_log_group : r => { type = "CWL", resource_arn = lg.arn } },
      anytrue([for cfg in values(var.agent_runtimes) : cfg.tracing]) ? { xray_traces = { type = "XRAY", resource_arn = null } } : {},
    )
    deliveries = merge(
      { for r in keys(var.agent_runtimes) : "${r}-logs" => { source = "${r}-logs", destination = r } },
      { for r, cfg in var.agent_runtimes : "${r}-traces" => { source = "${r}-traces", destination = "xray_traces" } if cfg.tracing },
    )
  }
}

module "runtime_logs" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.1.0"
  count   = length(var.agent_runtimes) > 0 ? 1 : 0

  name_prefix  = local.name_prefix
  sources      = local.log_delivery.sources
  destinations = local.log_delivery.destinations
  deliveries   = local.log_delivery.deliveries
}
