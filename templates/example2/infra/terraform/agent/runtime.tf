locals {
  # AgentCore names allow underscores only: <project>_<env>_<runtime> and <project>_<env>_memory. The iam stack grants
  # access by these names, so they must not change without changing iam/policies.tf.
  agentcore_name_prefix = replace(local.name_prefix, "-", "_")
  runtimes              = sort(jsondecode(module.shared.strings["agent_runtimes"]))
  ecr_urls              = jsondecode(module.shared.strings["ecr_repository_urls"])
  runtime_names         = { for r in local.runtimes : r => "${local.agentcore_name_prefix}_${replace(r, "-", "_")}" }
  memory_name           = "${local.agentcore_name_prefix}_memory"
  runtime_images        = { for r in local.runtimes : r => "${local.ecr_urls[r]}:${var.agent_image_tag}" }

  # Names avoid anything the agentcore-runtime module reads as a secret (TOKEN, KEY, ...).
  runtime_environment = merge(
    {
      AWS_REGION                = var.aws_region
      AGENT_MODEL_ID            = var.model_id
      AGENT_MEMORY_ID           = module.memory.memory_id
      AGENT_BACKEND_MODE        = var.backend_mode
      AGENT_MAX_OUTPUT_LENGTH   = tostring(var.max_output_length)
      AGENT_OUTPUT_GUARDRAIL_ID = module.output_guardrail.guardrail_id
    },
    # Absent is the only way to say "use the image default", so an empty URL is omitted rather than sent.
    var.backend_url == "" ? {} : { AGENT_BACKEND_URL = var.backend_url },
  )
}

module "memory" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/agentcore-memory/aws"
  version = "~> 0.1.0"

  name              = local.memory_name
  description       = "Short-term conversation memory of ${local.name_prefix}."
  event_expiry_days = var.memory_event_expiry_days
}

module "runtime" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/agentcore-runtime/aws"
  version = "~> 0.1.0"

  for_each = local.runtime_names

  name          = each.value
  description   = "AgentCore Runtime ${each.key} of ${local.name_prefix}."
  role_arn      = module.shared.strings["agent_runtime_role_arn"]
  container_uri = local.runtime_images[each.key]
  network = {
    subnet_ids         = module.shared.lists["agent_subnet_ids"]
    security_group_ids = [module.shared.strings["agent_sg_id"]]
  }
  environment_variables = local.runtime_environment
}
