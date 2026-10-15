mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111111111111" }
  }
}

variables {
  name_prefix = "alpha-dev"
  profiles = {
    chat = {
      copy_from   = "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0"
      description = "Chat model for alpha-dev"
    }
    judge = {
      copy_from = "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-3-5-sonnet-20240620-v1:0"
    }
  }
}

run "one_profile_per_entry" {
  command = plan

  assert {
    condition     = length(aws_bedrock_inference_profile.this) == 2
    error_message = "Expected one inference profile per entry"
  }
  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].name == "alpha-dev-chat" && aws_bedrock_inference_profile.this["judge"].name == "alpha-dev-judge"
    error_message = "name must be <name_prefix>-<key>"
  }
  assert {
    condition = (
      length(aws_bedrock_inference_profile.this["chat"].model_source) == 1 &&
      aws_bedrock_inference_profile.this["chat"].model_source[0].copy_from == "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0" &&
      aws_bedrock_inference_profile.this["judge"].model_source[0].copy_from == "arn:aws:bedrock:ap-northeast-1:111111111111:inference-profile/apac.anthropic.claude-3-5-sonnet-20240620-v1:0"
    )
    error_message = "model_source.copy_from must follow the input"
  }
  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].description == "Chat model for alpha-dev" && aws_bedrock_inference_profile.this["judge"].description == null
    error_message = "description must follow the input and default to null"
  }
}

run "tags_reach_every_profile_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha", CostCenter = "llm" }
  }

  assert {
    condition = (
      aws_bedrock_inference_profile.this["chat"].tags == tomap({ Project = "alpha", CostCenter = "llm", Name = "alpha-dev-chat" }) &&
      aws_bedrock_inference_profile.this["judge"].tags == tomap({ Project = "alpha", CostCenter = "llm", Name = "alpha-dev-judge" })
    )
    error_message = "tags must be applied to every profile, plus Name set to the profile name"
  }
}

run "empty_profiles_create_nothing" {
  command = plan

  variables {
    profiles = {}
  }

  assert {
    condition     = length(aws_bedrock_inference_profile.this) == 0
    error_message = "An empty map must create nothing"
  }
  assert {
    condition     = length(output.arns) == 0 && length(output.ids) == 0
    error_message = "Outputs must be empty maps when nothing is created"
  }
}

run "outputs" {
  command = plan

  override_resource {
    target          = aws_bedrock_inference_profile.this["chat"]
    override_during = plan
    values = {
      arn = "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/chat111"
      id  = "chat111"
    }
  }
  override_resource {
    target          = aws_bedrock_inference_profile.this["judge"]
    override_during = plan
    values = {
      arn = "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/judge222"
      id  = "judge222"
    }
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["chat", "judge"]) && toset(keys(output.ids)) == toset(["chat", "judge"])
    error_message = "Output keys must equal the profiles keys"
  }
  assert {
    condition     = output.arns["chat"] == "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/chat111" && output.arns["judge"] == "arn:aws:bedrock:ap-northeast-1:111111111111:application-inference-profile/judge222"
    error_message = "arns must expose the profile ARNs"
  }
  assert {
    condition     = output.ids["chat"] == "chat111" && output.ids["judge"] == "judge222"
    error_message = "ids must expose the profile ids"
  }
}

run "foundation_model_arn_accepted" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } }
  }

  assert {
    condition     = length(aws_bedrock_inference_profile.this) == 1
    error_message = "A foundation-model ARN must pass"
  }
}

run "system_inference_profile_arn_accepted" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1:111111111111:inference-profile/global.anthropic.claude-sonnet-4-20250514-v1:0" } }
  }

  assert {
    condition     = length(aws_bedrock_inference_profile.this) == 1
    error_message = "A system inference-profile ARN must pass"
  }
}

run "copy_from_not_arn_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "anthropic.claude-3-5-sonnet-20240620-v1:0" } }
  }

  expect_failures = [var.profiles]
}

run "copy_from_provisioned_model_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1:111111111111:provisioned-model/abc123" } }
  }

  expect_failures = [var.profiles]
}

run "copy_from_application_profile_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1:111111111111:application-inference-profile/abc123" } }
  }

  expect_failures = [var.profiles]
}

run "name_exactly_64_accepted" {
  command = plan

  variables {
    name_prefix = "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"                               # 60 chars
    profiles    = { abc = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } } # 60 + 1 + 3 = 64
  }

  assert {
    condition     = length(aws_bedrock_inference_profile.this) == 1
    error_message = "A 64 char name must pass"
  }
}

run "name_65_rejected" {
  command = plan

  variables {
    name_prefix = "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
    profiles    = { abcd = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } } # 65
  }

  expect_failures = [var.profiles]
}

run "name_allowed_characters_accepted" {
  command = plan

  variables {
    name_prefix = "alpha_dev.v1"
    profiles    = { "chat-main" = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } }
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["chat-main"].name == "alpha_dev.v1-chat-main"
    error_message = "Letters, digits, dot, underscore and single hyphens must pass"
  }
}

run "name_invalid_character_rejected" {
  command = plan

  variables {
    profiles = { "chat/main" = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } }
  }

  expect_failures = [var.profiles]
}

run "name_double_hyphen_rejected" {
  command = plan

  variables {
    profiles = { "-chat" = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0" } }
  }

  expect_failures = [var.profiles]
}

run "name_tag_without_input_tags" {
  command = plan

  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].tags == tomap({ Name = "alpha-dev-chat" })
    error_message = "Name must be added even when tags is empty"
  }
}

run "copy_from_foundation_model_wildcard_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.*" } }
  }

  expect_failures = [var.profiles]
}

run "copy_from_inference_profile_wildcard_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1:111111111111:inference-profile/apac.*" } }
  }

  expect_failures = [var.profiles]
}

run "copy_from_inference_profile_other_account_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1:222222222222:inference-profile/global.anthropic.claude-sonnet-4-20250514-v1:0" } }
  }

  expect_failures = [aws_bedrock_inference_profile.this]
}

run "copy_from_inference_profile_empty_account_rejected" {
  command = plan

  variables {
    profiles = { a = { copy_from = "arn:aws:bedrock:us-east-1::inference-profile/global.anthropic.claude-sonnet-4-20250514-v1:0" } }
  }

  expect_failures = [aws_bedrock_inference_profile.this]
}
