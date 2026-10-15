data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  cross_region_profile_arn = var.tier == "STANDARD" ? "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:guardrail-profile/${var.cross_region_profile_id}" : null

  grounding_filters = var.contextual_grounding == null ? [] : [
    for f in [
      { type = "GROUNDING", threshold = var.contextual_grounding.grounding_threshold },
      { type = "RELEVANCE", threshold = var.contextual_grounding.relevance_threshold },
    ] : f if f.threshold != null
  ]

  has_policy = (
    length(var.content_filters) > 0 ||
    length(var.denied_topics) > 0 ||
    length(var.words) > 0 ||
    length(var.managed_word_lists) > 0 ||
    length(var.pii_entities) > 0 ||
    length(var.regexes) > 0 ||
    length(local.grounding_filters) > 0
  )
}

resource "aws_bedrock_guardrail" "this" {
  name                      = var.name
  description               = var.description
  blocked_input_messaging   = var.blocked_input_message
  blocked_outputs_messaging = var.blocked_output_message
  kms_key_arn               = var.kms_key_arn

  dynamic "cross_region_config" {
    for_each = local.cross_region_profile_arn == null ? [] : [local.cross_region_profile_arn]
    content {
      guardrail_profile_identifier = cross_region_config.value
    }
  }

  # Every policy block is omitted when its input is empty: Bedrock rejects empty lists.
  dynamic "content_policy_config" {
    for_each = length(var.content_filters) > 0 ? [1] : []
    content {
      # tier_config is optional and computed; leaving it out silently means CLASSIC, which only evaluates English.
      tier_config = [{ tier_name = var.tier }]

      dynamic "filters_config" {
        for_each = var.content_filters
        content {
          type            = filters_config.key
          input_strength  = filters_config.value.input_strength
          output_strength = filters_config.value.output_strength
          input_action    = filters_config.value.input_action
          output_action   = filters_config.value.output_action
          input_enabled   = filters_config.value.input_enabled
          output_enabled  = filters_config.value.output_enabled
        }
      }
    }
  }

  dynamic "topic_policy_config" {
    for_each = length(var.denied_topics) > 0 ? [1] : []
    content {
      tier_config = [{ tier_name = var.tier }]

      dynamic "topics_config" {
        for_each = var.denied_topics
        content {
          name       = topics_config.key
          definition = topics_config.value.definition
          examples   = topics_config.value.examples
          type       = "DENY"
        }
      }
    }
  }

  dynamic "word_policy_config" {
    for_each = length(var.words) + length(var.managed_word_lists) > 0 ? [1] : []
    content {
      dynamic "words_config" {
        for_each = var.words
        content {
          text = words_config.value
        }
      }

      dynamic "managed_word_lists_config" {
        for_each = var.managed_word_lists
        content {
          type = managed_word_lists_config.value
        }
      }
    }
  }

  dynamic "sensitive_information_policy_config" {
    for_each = length(var.pii_entities) + length(var.regexes) > 0 ? [1] : []
    content {
      dynamic "pii_entities_config" {
        for_each = var.pii_entities
        content {
          type           = pii_entities_config.key
          action         = pii_entities_config.value.action
          input_enabled  = pii_entities_config.value.input_enabled
          output_enabled = pii_entities_config.value.output_enabled
        }
      }

      dynamic "regexes_config" {
        for_each = var.regexes
        content {
          name        = regexes_config.key
          pattern     = regexes_config.value.pattern
          action      = regexes_config.value.action
          description = regexes_config.value.description
        }
      }
    }
  }

  dynamic "contextual_grounding_policy_config" {
    for_each = length(local.grounding_filters) > 0 ? [1] : []
    content {
      dynamic "filters_config" {
        for_each = local.grounding_filters
        content {
          type      = filters_config.value.type
          threshold = filters_config.value.threshold
        }
      }
    }
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = local.has_policy
      error_message = "At least one of content_filters, denied_topics, words, managed_word_lists, pii_entities, regexes or contextual_grounding must be set."
    }
  }
}
