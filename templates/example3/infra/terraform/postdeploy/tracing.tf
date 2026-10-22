locals {
  runtime_arns = jsondecode(module.in.strings["agent_runtime_arns"])

  trace_sources = merge(
    { for k, arn in local.runtime_arns : "runtime-${k}" => { resource_arn = arn, log_type = "TRACES" } },
    { memory = { resource_arn = module.in.strings["agent_memory_arn"], log_type = "TRACES" } },
  )
  trace_destinations = { xray = { type = "XRAY" } }
  trace_deliveries   = { for k in keys(local.trace_sources) : k => { source = k, destination = "xray" } }
}

module "traces" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/log-delivery/aws"
  version = "~> 0.1.0"

  count = var.tracing_enabled ? 1 : 0

  name_prefix  = "${local.name_prefix}-traces"
  sources      = local.trace_sources
  destinations = local.trace_destinations
  deliveries   = local.trace_deliveries
}
