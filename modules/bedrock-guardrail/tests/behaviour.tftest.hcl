mock_provider "aws" {
  # Generate computed values at plan time, so an omitted optional-computed attribute such as
  # tier_config fails an assertion instead of staying unknown.
  mock_resource "aws_bedrock_guardrail" {
    override_during = plan
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "ap-northeast-1" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }
}

variables {
  name                    = "alpha-dev-input"
  blocked_input_message   = "blocked input"
  blocked_output_message  = "blocked output"
  cross_region_profile_id = "apac.guardrail.v1:0"
  content_filters = {
    HATE = { input_strength = "HIGH", output_strength = "MEDIUM" }
  }
  denied_topics = {
    investment = { definition = "Advice on stocks or funds." }
  }
}

run "defaults_standard" {
  command = plan

  assert {
    condition     = aws_bedrock_guardrail.this.content_policy_config[0].tier_config == tolist([{ tier_name = "STANDARD" }])
    error_message = "content_policy_config must carry tier STANDARD by default"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.topic_policy_config[0].tier_config == tolist([{ tier_name = "STANDARD" }])
    error_message = "topic_policy_config must carry tier STANDARD by default"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.cross_region_config[0].guardrail_profile_identifier == "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail-profile/apac.guardrail.v1:0"
    error_message = "cross_region_config must be the profile ARN built from partition, region and account"
  }

  assert {
    condition     = output.cross_region_profile_arn == "arn:aws:bedrock:ap-northeast-1:111111111111:guardrail-profile/apac.guardrail.v1:0"
    error_message = "cross_region_profile_arn output must equal the profile ARN"
  }

  assert {
    condition     = output.cross_region_profile_id == "apac.guardrail.v1:0"
    error_message = "cross_region_profile_id output must equal the input"
  }

  assert {
    condition     = output.version == "DRAFT"
    error_message = "version output must always be DRAFT"
  }

  assert {
    condition     = output.name == "alpha-dev-input"
    error_message = "name output must equal the name input"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.blocked_input_messaging == "blocked input" && aws_bedrock_guardrail.this.blocked_outputs_messaging == "blocked output"
    error_message = "Blocked messages must follow the inputs"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.tags == tomap({ Name = "alpha-dev-input" })
    error_message = "Without tags input the only tag is Name"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.kms_key_arn == null
    error_message = "kms_key_arn must be null by default"
  }

  assert {
    condition = length([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f
      if f.type == "HATE" && f.input_strength == "HIGH" && f.output_strength == "MEDIUM" &&
      f.input_action == "BLOCK" && f.output_action == "BLOCK" && f.input_enabled && f.output_enabled
    ]) == 1
    error_message = "A content filter must map type, strengths and default BLOCK actions with both sides enabled"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.word_policy_config) == 0 && length(aws_bedrock_guardrail.this.sensitive_information_policy_config) == 0 && length(aws_bedrock_guardrail.this.contextual_grounding_policy_config) == 0
    error_message = "Policies without input must not be sent"
  }
}

run "classic_tier" {
  command = plan

  variables {
    tier                    = "CLASSIC"
    cross_region_profile_id = null
  }

  assert {
    condition     = aws_bedrock_guardrail.this.content_policy_config[0].tier_config == tolist([{ tier_name = "CLASSIC" }])
    error_message = "content_policy_config must carry tier CLASSIC when asked"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.topic_policy_config[0].tier_config == tolist([{ tier_name = "CLASSIC" }])
    error_message = "topic_policy_config must carry tier CLASSIC when asked"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.cross_region_config) == 0
    error_message = "CLASSIC must not send cross_region_config"
  }

  assert {
    condition     = output.cross_region_profile_arn == null && output.cross_region_profile_id == null
    error_message = "CLASSIC must output null profile ARN and id"
  }
}

run "only_words" {
  command = plan

  variables {
    content_filters = {}
    denied_topics   = {}
    words           = ["forbidden"]
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.word_policy_config) == 1
    error_message = "words must produce word_policy_config"
  }

  assert {
    condition     = [for w in aws_bedrock_guardrail.this.word_policy_config[0].words_config : w.text] == ["forbidden"]
    error_message = "words_config must list the words"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.word_policy_config[0].managed_word_lists_config) == 0
    error_message = "No managed word list unless asked"
  }

  assert {
    condition = (
      length(aws_bedrock_guardrail.this.content_policy_config) == 0 &&
      length(aws_bedrock_guardrail.this.topic_policy_config) == 0 &&
      length(aws_bedrock_guardrail.this.sensitive_information_policy_config) == 0 &&
      length(aws_bedrock_guardrail.this.contextual_grounding_policy_config) == 0
    )
    error_message = "With only words, every other policy block must be absent"
  }
}

run "no_topics_no_topic_policy" {
  command = plan

  variables {
    denied_topics = {}
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.topic_policy_config) == 0
    error_message = "Empty denied_topics must not send topic_policy_config"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.content_policy_config) == 1
    error_message = "content_policy_config must still be sent"
  }
}

run "topics_mapped" {
  command = plan

  variables {
    denied_topics = {
      investment = { definition = "Advice on stocks or funds.", examples = ["Which fund should I buy?"] }
    }
  }

  assert {
    condition = aws_bedrock_guardrail.this.topic_policy_config[0].topics_config == tolist([{
      name       = "investment"
      definition = "Advice on stocks or funds."
      examples   = tolist(["Which fund should I buy?"])
      type       = "DENY"
    }])
    error_message = "Each denied topic must map to a DENY topic with its name, definition and examples"
  }
}

run "prompt_attack_output_none_kept" {
  command = plan

  variables {
    content_filters = {
      PROMPT_ATTACK = { input_strength = "HIGH", output_strength = "NONE" }
    }
  }

  assert {
    condition = length([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f
      if f.type == "PROMPT_ATTACK" && f.input_strength == "HIGH" && f.output_strength == "NONE"
    ]) == 1
    error_message = "PROMPT_ATTACK must keep output_strength NONE as given"
  }
}

run "content_filter_overrides" {
  command = plan

  variables {
    content_filters = {
      INSULTS = { input_strength = "LOW", output_strength = "LOW", input_action = "NONE", output_enabled = false }
    }
  }

  assert {
    condition = length([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f
      if f.type == "INSULTS" && f.input_action == "NONE" && f.output_action == "BLOCK" && f.input_enabled && !f.output_enabled
    ]) == 1
    error_message = "Content filter action and enabled overrides must be kept"
  }
}

run "sensitive_information_and_grounding" {
  command = plan

  variables {
    managed_word_lists = ["PROFANITY"]
    pii_entities = {
      EMAIL = { action = "ANONYMIZE", input_enabled = false }
    }
    regexes = {
      order-id = { pattern = "ORD-[0-9]{8}", action = "BLOCK", description = "Order id" }
    }
    contextual_grounding = {
      grounding_threshold = 0.99
      relevance_threshold = 0
    }
  }

  assert {
    condition     = [for m in aws_bedrock_guardrail.this.word_policy_config[0].managed_word_lists_config : m.type] == ["PROFANITY"]
    error_message = "managed_word_lists must map to managed_word_lists_config"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.word_policy_config[0].words_config) == 0
    error_message = "No custom words unless asked"
  }

  assert {
    condition = (
      length(aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config) == 1 &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config[0].type == "EMAIL" &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config[0].action == "ANONYMIZE" &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config[0].input_enabled == false &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config[0].output_enabled == true
    )
    error_message = "PII entity must map type, action and enabled flags"
  }

  assert {
    condition = (
      length(aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config) == 1 &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config[0].name == "order-id" &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config[0].pattern == "ORD-[0-9]{8}" &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config[0].action == "BLOCK" &&
      aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config[0].description == "Order id"
    )
    error_message = "Regex must map name, pattern, action and description"
  }

  assert {
    condition = aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config == tolist([
      { type = "GROUNDING", threshold = 0.99 },
      { type = "RELEVANCE", threshold = 0 },
    ])
    error_message = "Grounding thresholds must map to GROUNDING and RELEVANCE filters"
  }
}

run "only_relevance_threshold" {
  command = plan

  variables {
    contextual_grounding = { relevance_threshold = 0.5 }
  }

  assert {
    condition     = aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config == tolist([{ type = "RELEVANCE", threshold = 0.5 }])
    error_message = "An unset threshold must not produce a filter"
  }
}

run "pii_only_has_no_regexes" {
  command = plan

  variables {
    pii_entities = { PHONE = { action = "BLOCK" } }
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.sensitive_information_policy_config[0].regexes_config) == 0
    error_message = "No regexes_config unless regexes are given"
  }
}

run "description_kms_tags" {
  command = plan

  variables {
    description = "Input guardrail"
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    tags        = { Project = "alpha" }
  }

  assert {
    condition     = aws_bedrock_guardrail.this.description == "Input guardrail"
    error_message = "description must follow the input"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_arn must follow the input"
  }

  assert {
    condition     = aws_bedrock_guardrail.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-input" })
    error_message = "Input tags must be kept and Name added"
  }
}
