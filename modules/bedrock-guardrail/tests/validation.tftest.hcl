mock_provider "aws" {}

variables {
  name                    = "alpha-dev-input"
  blocked_input_message   = "blocked input"
  blocked_output_message  = "blocked output"
  cross_region_profile_id = "apac.guardrail.v1:0"
  content_filters = {
    HATE = { input_strength = "HIGH", output_strength = "HIGH" }
  }
}

run "name_50_chars_passes" {
  command = plan

  variables {
    name = format("%050d", 0)
  }
}

run "name_51_chars_rejected" {
  command = plan

  variables {
    name = format("%051d", 0)
  }

  expect_failures = [var.name]
}

run "name_with_space_rejected" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "tier_premium_rejected" {
  command = plan

  variables {
    tier                    = "PREMIUM"
    cross_region_profile_id = null
  }

  expect_failures = [var.tier]
}

run "standard_without_profile_rejected" {
  command = plan

  variables {
    cross_region_profile_id = null
  }

  expect_failures = [var.cross_region_profile_id]
}

run "standard_with_profile_passes" {
  command = plan

  variables {
    cross_region_profile_id = "apac.guardrail.v1:0"
  }
}

run "classic_with_profile_rejected" {
  command = plan

  variables {
    tier = "CLASSIC"
  }

  expect_failures = [var.cross_region_profile_id]
}

run "classic_without_profile_passes" {
  command = plan

  variables {
    tier                    = "CLASSIC"
    cross_region_profile_id = null
  }
}

run "profile_bad_format_rejected" {
  command = plan

  variables {
    cross_region_profile_id = "apac-guardrail-v1"
  }

  expect_failures = [var.cross_region_profile_id]
}

run "profile_with_region_group_suffix_passes" {
  command = plan

  variables {
    cross_region_profile_id = "us-gov.guardrail.v1:0"
  }
}

run "topics_30_pass" {
  command = plan

  variables {
    denied_topics = { for i in range(30) : "topic-${i}" => { definition = "Topic ${i}." } }
  }
}

run "topics_31_rejected" {
  command = plan

  variables {
    denied_topics = { for i in range(31) : "topic-${i}" => { definition = "Topic ${i}." } }
  }

  expect_failures = [var.denied_topics]
}

run "topic_empty_definition_rejected" {
  command = plan

  variables {
    denied_topics = { investment = { definition = " " } }
  }

  expect_failures = [var.denied_topics]
}

run "no_policy_rejected" {
  command = plan

  variables {
    content_filters = {}
  }

  expect_failures = [aws_bedrock_guardrail.this]
}

run "single_word_is_enough" {
  command = plan

  variables {
    content_filters = {}
    words           = ["forbidden"]
  }
}

run "single_managed_word_list_is_enough" {
  command = plan

  variables {
    content_filters    = {}
    managed_word_lists = ["PROFANITY"]
  }
}

run "managed_word_list_unknown_rejected" {
  command = plan

  variables {
    managed_word_lists = ["SLANG"]
  }

  expect_failures = [var.managed_word_lists]
}

run "strength_extreme_rejected" {
  command = plan

  variables {
    content_filters = {
      HATE = { input_strength = "EXTREME", output_strength = "HIGH" }
    }
  }

  expect_failures = [var.content_filters]
}

run "strength_none_and_low_pass" {
  command = plan

  variables {
    content_filters = {
      HATE = { input_strength = "NONE", output_strength = "LOW" }
    }
  }
}

run "content_action_allow_rejected" {
  command = plan

  variables {
    content_filters = {
      HATE = { input_strength = "HIGH", output_strength = "HIGH", output_action = "ALLOW" }
    }
  }

  expect_failures = [var.content_filters]
}

run "content_action_none_passes" {
  command = plan

  variables {
    content_filters = {
      HATE = { input_strength = "HIGH", output_strength = "HIGH", input_action = "NONE", output_action = "NONE" }
    }
  }
}

run "content_filter_key_spam_rejected" {
  command = plan

  variables {
    content_filters = {
      SPAM = { input_strength = "HIGH", output_strength = "HIGH" }
    }
  }

  expect_failures = [var.content_filters]
}

run "all_content_filter_keys_pass" {
  command = plan

  variables {
    content_filters = {
      for k in ["SEXUAL", "VIOLENCE", "HATE", "INSULTS", "MISCONDUCT"] : k => { input_strength = "HIGH", output_strength = "HIGH" }
    }
  }
}

run "prompt_attack_output_high_rejected" {
  command = plan

  variables {
    content_filters = {
      PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "HIGH" }
    }
  }

  expect_failures = [var.content_filters]
}

run "prompt_attack_output_none_passes" {
  command = plan

  variables {
    content_filters = {
      PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
    }
  }
}

run "pii_action_mask_rejected" {
  command = plan

  variables {
    pii_entities = { EMAIL = { action = "MASK" } }
  }

  expect_failures = [var.pii_entities]
}

run "pii_action_anonymize_passes" {
  command = plan

  variables {
    pii_entities = { EMAIL = { action = "ANONYMIZE" } }
  }
}

run "regex_action_mask_rejected" {
  command = plan

  variables {
    regexes = { order-id = { pattern = "ORD-[0-9]{8}", action = "MASK" } }
  }

  expect_failures = [var.regexes]
}

run "regex_action_anonymize_passes" {
  command = plan

  variables {
    regexes = { order-id = { pattern = "ORD-[0-9]{8}", action = "ANONYMIZE" } }
  }
}

run "grounding_threshold_1_rejected" {
  command = plan

  variables {
    contextual_grounding = { grounding_threshold = 1.0 }
  }

  expect_failures = [var.contextual_grounding]
}

run "grounding_threshold_negative_rejected" {
  command = plan

  variables {
    contextual_grounding = { relevance_threshold = -0.1 }
  }

  expect_failures = [var.contextual_grounding]
}

run "grounding_threshold_099_passes" {
  command = plan

  variables {
    contextual_grounding = { grounding_threshold = 0.99, relevance_threshold = 0 }
  }
}

run "grounding_without_threshold_rejected" {
  command = plan

  variables {
    contextual_grounding = {}
  }

  expect_failures = [var.contextual_grounding]
}

run "only_grounding_is_enough" {
  command = plan

  variables {
    content_filters      = {}
    contextual_grounding = { grounding_threshold = 0.5 }
  }
}

# pii_entities keys

run "pii_all_documented_types_pass" {
  command = plan

  variables {
    pii_entities = {
      for t in [
        "ADDRESS", "AGE", "AWS_ACCESS_KEY", "AWS_SECRET_KEY", "CA_HEALTH_NUMBER", "CA_SOCIAL_INSURANCE_NUMBER",
        "CREDIT_DEBIT_CARD_CVV", "CREDIT_DEBIT_CARD_EXPIRY", "CREDIT_DEBIT_CARD_NUMBER", "DRIVER_ID", "EMAIL",
        "INTERNATIONAL_BANK_ACCOUNT_NUMBER", "IP_ADDRESS", "LICENSE_PLATE", "MAC_ADDRESS", "NAME", "PASSWORD", "PHONE",
        "PIN", "SWIFT_CODE", "UK_NATIONAL_HEALTH_SERVICE_NUMBER", "UK_NATIONAL_INSURANCE_NUMBER",
        "UK_UNIQUE_TAXPAYER_REFERENCE_NUMBER", "URL", "USERNAME", "US_BANK_ACCOUNT_NUMBER", "US_BANK_ROUTING_NUMBER",
        "US_INDIVIDUAL_TAX_IDENTIFICATION_NUMBER", "US_PASSPORT_NUMBER", "US_SOCIAL_SECURITY_NUMBER",
        "VEHICLE_IDENTIFICATION_NUMBER",
      ] : t => { action = "BLOCK" }
    }
  }
}

run "pii_unknown_type_rejected" {
  command = plan

  variables {
    pii_entities = { SSN = { action = "BLOCK" } }
  }

  expect_failures = [var.pii_entities]
}

run "pii_lowercase_type_rejected" {
  command = plan

  variables {
    pii_entities = { email = { action = "BLOCK" } }
  }

  expect_failures = [var.pii_entities]
}

# kms_key_arn

run "kms_key_arn_key_passes" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-4e5f-6789-abcd-ef0123456789"
  }
}

run "kms_key_arn_multi_region_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
  }
}

run "kms_key_arn_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_wildcard_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/*"
  }

  expect_failures = [var.kms_key_arn]
}
