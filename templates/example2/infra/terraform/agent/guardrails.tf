locals {
  # Strength lives on the block, not on the profile, so every profile that picks a filter gets the same strength.
  guardrail_input_strengths = {
    HATE          = "MEDIUM"
    INSULTS       = "MEDIUM"
    SEXUAL        = "MEDIUM"
    VIOLENCE      = "MEDIUM"
    MISCONDUCT    = "MEDIUM"
    PROMPT_ATTACK = "HIGH"
  }

  # Illustrative topics: replace them with the policy of the real product.
  guardrail_topic_blocks = {
    InvestmentAdvice = {
      definition = "The user asks which specific financial products or assets to buy or sell, or how to allocate savings among them."
      examples   = ["Which stock should I buy this month?", "Should I move all my savings into one fund?"]
    }
    MedicalAdvice = {
      definition = "The user asks for a diagnosis, a treatment plan or a medicine dose for a health condition."
      examples   = ["What dose of this medicine should I take?", "Do these symptoms mean I have a serious illness?"]
    }
  }

  # Named groups of exact-match words. The words are illustrative.
  guardrail_word_blocks = {
    SampleTerms = ["sample-blocked-term", "another-sample-term"]
  }

  guardrail_profile_base = {
    content = keys(local.guardrail_input_strengths)
    topics  = keys(local.guardrail_topic_blocks)
    words   = []
  }

  guardrail_profiles = {
    # Screens every request that has no profile of its own.
    default = merge(local.guardrail_profile_base, {
      blocked_message = "這部分我沒辦法協助。"
    })
    profile_a = merge(local.guardrail_profile_base, {
      words           = ["SampleTerms"]
      blocked_message = "這部分我沒辦法協助，換個話題聊聊吧。"
    })
  }

  # words: the block names resolved to the words themselves, first occurrence kept (a list, because the order is
  # significant to the provider).
  guardrail_input_targets = {
    for profile, spec in local.guardrail_profiles : profile => merge(spec, {
      name  = "${local.name_prefix}-input-${profile}"
      words = distinct(flatten([for b in spec.words : local.guardrail_word_blocks[b]]))
      # The input guardrails are applied to prompts only.
      content_filters = {
        for c in spec.content : c => {
          input_strength  = local.guardrail_input_strengths[c]
          output_strength = "NONE"
          output_enabled  = false
        }
      }
      topics = { for t in spec.topics : t => local.guardrail_topic_blocks[t] }
    })
  }

  guardrail_output_name = "${local.name_prefix}-output"

  # The output guardrail screens generated text; the API rejects a prompt attack filter on the output side.
  guardrail_output_content_filters = {
    for c in ["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT"] : c => {
      input_strength  = "NONE"
      output_strength = local.guardrail_input_strengths[c]
      input_enabled   = false
      output_enabled  = true
    }
  }

  guardrail_blocked_output_message = "抱歉，這段回覆我無法提供。"
}

module "input_guardrail" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/bedrock-guardrail/aws"
  version = "~> 0.1.0"

  for_each = local.guardrail_input_targets

  name                    = each.value.name
  description             = "Input guardrail, profile ${each.key}."
  blocked_input_message   = each.value.blocked_message
  blocked_output_message  = local.guardrail_blocked_output_message
  cross_region_profile_id = var.guardrail_profile_id
  content_filters         = each.value.content_filters
  denied_topics           = each.value.topics
  words                   = each.value.words
}

module "output_guardrail" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/bedrock-guardrail/aws"
  version = "~> 0.1.0"

  name                    = local.guardrail_output_name
  description             = "Output guardrail applied by the Runtime to generated text."
  blocked_input_message   = local.guardrail_profiles["default"].blocked_message
  blocked_output_message  = local.guardrail_blocked_output_message
  cross_region_profile_id = var.guardrail_profile_id
  content_filters         = local.guardrail_output_content_filters
}
