locals {
  published_strings = {
    # SSM rejects a map, so these are JSON in a String: Runtime name => ARN, and profile (or output) => guardrail id.
    agent_runtime_arns = jsonencode({ for r, m in module.runtime : r => m.runtime_arn })
    agent_memory_id    = module.memory.memory_id
    agent_memory_arn   = module.memory.memory_arn
    guardrail_ids = jsonencode(merge(
      { for p, m in module.input_guardrail : p => m.guardrail_id },
      { output = module.output_guardrail.guardrail_id },
    ))
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "agent"
  strings    = local.published_strings
}
