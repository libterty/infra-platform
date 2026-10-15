mock_provider "aws" {}

variables {
  name = "alpha_dev_chat"
}

# name

run "name_48_chars_accepted" {
  command = plan

  variables {
    name = "a23456789012345678901234567890123456789012345678"
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.name == "a23456789012345678901234567890123456789012345678"
    error_message = "A 48 char name must pass"
  }
}

run "name_49_chars_rejected" {
  command = plan

  variables {
    name = "a234567890123456789012345678901234567890123456789"
  }

  expect_failures = [var.name]
}

run "name_with_hyphen_rejected" {
  command = plan

  variables {
    name = "alpha-dev-chat"
  }

  expect_failures = [var.name]
}

run "name_starting_with_digit_rejected" {
  command = plan

  variables {
    name = "1alpha_dev_chat"
  }

  expect_failures = [var.name]
}

# event_expiry_days

# The aws provider 6.69.0 enforces 7-365 at plan time, so the lower edge is 7, not 3.
run "event_expiry_lower_edge_accepted" {
  command = plan

  variables {
    event_expiry_days = 7
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.event_expiry_duration == 7
    error_message = "event_expiry_days = 7 must pass"
  }
}

run "event_expiry_6_rejected" {
  command = plan

  variables {
    event_expiry_days = 6
  }

  expect_failures = [var.event_expiry_days]
}

run "event_expiry_3_rejected" {
  command = plan

  variables {
    event_expiry_days = 3
  }

  expect_failures = [var.event_expiry_days]
}

run "event_expiry_upper_edge_accepted" {
  command = plan

  variables {
    event_expiry_days = 365
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.event_expiry_duration == 365
    error_message = "event_expiry_days = 365 must pass"
  }
}

run "event_expiry_2_rejected" {
  command = plan

  variables {
    event_expiry_days = 2
  }

  expect_failures = [var.event_expiry_days]
}

run "event_expiry_366_rejected" {
  command = plan

  variables {
    event_expiry_days = 366
  }

  expect_failures = [var.event_expiry_days]
}

run "event_expiry_2_5_rejected" {
  command = plan

  variables {
    event_expiry_days = 2.5
  }

  expect_failures = [var.event_expiry_days]
}

# 90.5 is inside the range, so only the whole-number check can reject it.
run "event_expiry_fraction_in_range_rejected" {
  command = plan

  variables {
    event_expiry_days = 90.5
  }

  expect_failures = [var.event_expiry_days]
}

# strategies

run "strategy_builtin_types_accepted" {
  command = plan

  variables {
    strategies = {
      a = { type = "SEMANTIC", namespaces = ["/a"] }
      b = { type = "SUMMARIZATION", namespaces = ["/b/{sessionId}"] }
      c = { type = "USER_PREFERENCE", namespaces = ["/c"] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_memory_strategy.this) == 3
    error_message = "The three built-in strategy types must pass"
  }
}

run "strategy_custom_type_rejected" {
  command = plan

  variables {
    strategies = {
      a = { type = "CUSTOM", namespaces = ["/a"] }
    }
  }

  expect_failures = [var.strategies]
}

run "strategy_empty_namespaces_rejected" {
  command = plan

  variables {
    strategies = {
      a = { type = "SEMANTIC", namespaces = [] }
    }
  }

  expect_failures = [var.strategies]
}

run "strategy_namespace_without_slash_rejected" {
  command = plan

  variables {
    strategies = {
      a = { type = "SEMANTIC", namespaces = ["/ok", "actors/{actorId}"] }
    }
  }

  expect_failures = [var.strategies]
}

run "strategy_key_48_chars_accepted" {
  command = plan

  variables {
    strategies = {
      s23456789012345678901234567890123456789012345678 = { type = "SEMANTIC", namespaces = ["/a"] }
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_memory_strategy.this) == 1
    error_message = "A 48 char strategy key with letters, digits and underscores must pass"
  }
}

run "strategy_key_with_hyphen_rejected" {
  command = plan

  variables {
    strategies = {
      user-facts = { type = "SEMANTIC", namespaces = ["/a"] }
    }
  }

  expect_failures = [var.strategies]
}

run "strategy_key_49_chars_rejected" {
  command = plan

  variables {
    strategies = {
      s234567890123456789012345678901234567890123456789 = { type = "SEMANTIC", namespaces = ["/a"] }
    }
  }

  expect_failures = [var.strategies]
}

# kms_key_arn

run "kms_key_arn_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-4e5f-6789-abcd-ef0123456789"
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.encryption_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/0a1b2c3d-4e5f-6789-abcd-ef0123456789"
    error_message = "A KMS key ARN must pass"
  }
}

run "kms_key_arn_multi_region_key_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.encryption_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
    error_message = "A KMS key ARN must pass"
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
