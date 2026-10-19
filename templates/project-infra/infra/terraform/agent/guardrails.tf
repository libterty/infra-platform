# Guardrails and Memories use AWS owned keys: which conditions the project key would need for Bedrock and AgentCore
# has not been tested.
module "guardrail" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/bedrock-guardrail/aws"
  version  = "~> 0.1.0"
  for_each = var.guardrails

  name                    = "${local.name_prefix}-${each.key}"
  description             = each.value.description
  blocked_input_message   = each.value.blocked_input_message
  blocked_output_message  = each.value.blocked_output_message
  tier                    = each.value.tier
  cross_region_profile_id = each.value.cross_region_profile_id
  content_filters         = each.value.content_filters
  denied_topics           = each.value.denied_topics
  words                   = each.value.words
  managed_word_lists      = each.value.managed_word_lists
  pii_entities            = each.value.pii_entities
  regexes                 = each.value.regexes
  contextual_grounding    = each.value.contextual_grounding
  kms_key_arn             = null
}

module "memory" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/agentcore-memory/aws"
  version  = "~> 0.1.0"
  for_each = var.memories

  name              = replace("${local.name_prefix}-${each.key}", "-", "_")
  event_expiry_days = each.value.event_expiry_days
  strategies        = each.value.strategies
  kms_key_arn       = null
}
