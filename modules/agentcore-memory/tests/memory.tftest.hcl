mock_provider "aws" {}

variables {
  name = "alpha_dev_chat"
}

run "short_term_only_by_default" {
  command = plan

  assert {
    condition     = aws_bedrockagentcore_memory.this.name == "alpha_dev_chat"
    error_message = "name must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.event_expiry_duration == 90
    error_message = "event_expiry_duration must default to 90"
  }
  assert {
    condition     = length(aws_bedrockagentcore_memory_strategy.this) == 0
    error_message = "strategies = {} must create no strategy"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.description == null && aws_bedrockagentcore_memory.this.encryption_key_arn == null
    error_message = "description and encryption_key_arn must default to null"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.memory_execution_role_arn == null
    error_message = "Built-in strategies only; no memory execution role must be sent"
  }
}

run "memory_fields_follow_input" {
  command = plan

  variables {
    description       = "Chat history"
    event_expiry_days = 30
    kms_key_arn       = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    tags              = { Project = "alpha" }
  }

  assert {
    condition     = aws_bedrockagentcore_memory.this.event_expiry_duration == 30
    error_message = "event_expiry_duration must follow event_expiry_days"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.description == "Chat history"
    error_message = "description must follow the input"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.encryption_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "encryption_key_arn must follow kms_key_arn"
  }
  assert {
    condition     = aws_bedrockagentcore_memory.this.tags == tomap({ Project = "alpha", Name = "alpha_dev_chat" })
    error_message = "tags must be the input plus Name"
  }
}

run "strategies_follow_input" {
  command = plan

  variables {
    strategies = {
      facts   = { type = "SEMANTIC", namespaces = ["/actors/{actorId}/facts"], description = "Facts" }
      summary = { type = "SUMMARIZATION", namespaces = ["/summaries/{actorId}/{sessionId}"] }
      prefs   = { type = "USER_PREFERENCE", namespaces = ["/actors/{actorId}/preferences", "/shared/preferences"] }
    }
  }

  override_resource {
    target          = aws_bedrockagentcore_memory.this
    override_during = plan
    values          = { id = "alpha_dev_chat-AbCdEf1234" }
  }

  assert {
    condition     = length(aws_bedrockagentcore_memory_strategy.this) == 3
    error_message = "Expected one strategy per entry"
  }
  assert {
    condition     = alltrue([for s in aws_bedrockagentcore_memory_strategy.this : s.memory_id == "alpha_dev_chat-AbCdEf1234"])
    error_message = "Every strategy must point at the Memory id"
  }
  assert {
    condition = (
      aws_bedrockagentcore_memory_strategy.this["facts"].type == "SEMANTIC" &&
      aws_bedrockagentcore_memory_strategy.this["summary"].type == "SUMMARIZATION" &&
      aws_bedrockagentcore_memory_strategy.this["prefs"].type == "USER_PREFERENCE"
    )
    error_message = "type must follow the input"
  }
  assert {
    condition = (
      aws_bedrockagentcore_memory_strategy.this["facts"].namespace_templates == toset(["/actors/{actorId}/facts"]) &&
      aws_bedrockagentcore_memory_strategy.this["prefs"].namespace_templates == toset(["/actors/{actorId}/preferences", "/shared/preferences"])
    )
    error_message = "namespace_templates must follow the namespaces input"
  }
  assert {
    condition     = aws_bedrockagentcore_memory_strategy.this["facts"].name == "facts" && aws_bedrockagentcore_memory_strategy.this["summary"].name == "summary"
    error_message = "Strategy name must be the map key"
  }
  assert {
    condition     = aws_bedrockagentcore_memory_strategy.this["facts"].description == "Facts"
    error_message = "description must follow the input"
  }
  assert {
    condition     = alltrue([for s in aws_bedrockagentcore_memory_strategy.this : length(s.configuration) == 0 && s.memory_execution_role_arn == null])
    error_message = "Built-in strategies must not send configuration or a memory execution role"
  }
}

run "outputs" {
  command = plan

  variables {
    strategies = {
      facts = { type = "SEMANTIC", namespaces = ["/actors/{actorId}/facts"] }
    }
  }

  override_resource {
    target          = aws_bedrockagentcore_memory.this
    override_during = plan
    values = {
      id  = "alpha_dev_chat-AbCdEf1234"
      arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_chat-AbCdEf1234"
    }
  }
  override_resource {
    target          = aws_bedrockagentcore_memory_strategy.this["facts"]
    override_during = plan
    values          = { memory_strategy_id = "facts-XyZ0987654" }
  }

  assert {
    condition     = output.memory_id == "alpha_dev_chat-AbCdEf1234"
    error_message = "memory_id must expose the Memory id"
  }
  assert {
    condition     = output.memory_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_chat-AbCdEf1234"
    error_message = "memory_arn must expose the Memory ARN"
  }
  assert {
    condition     = toset(keys(output.strategy_ids)) == toset(["facts"]) && output.strategy_ids["facts"] == "facts-XyZ0987654"
    error_message = "strategy_ids must map each strategies key to its memory_strategy_id"
  }
}

run "outputs_empty_strategies" {
  command = plan

  assert {
    condition     = length(output.strategy_ids) == 0
    error_message = "strategy_ids must be empty when there are no strategies"
  }
}
