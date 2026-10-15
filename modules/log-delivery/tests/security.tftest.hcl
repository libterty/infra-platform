mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  name_prefix = "alpha-dev"

  sources = {
    chat-logs = {
      resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
      log_type     = "APPLICATION_LOGS"
    }
  }

  destinations = {
    chat = {
      type         = "CWL"
      resource_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
    }
  }
}

# Source resource_arn format

run "source_not_an_arn_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = { resource_arn = "alpha_dev_chat-AbCdEf1234", log_type = "APPLICATION_LOGS" }
    }
  }

  expect_failures = [var.sources]
}

run "source_arn_without_account_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = { resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1::runtime/alpha_dev_chat-AbCdEf1234", log_type = "APPLICATION_LOGS" }
    }
  }

  expect_failures = [var.sources]
}

run "source_same_account_accepted" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].resource_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
    error_message = "A source in the current account must pass"
  }
}

# Same-account guard on sources

run "source_other_account_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = { resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:222222222222:runtime/alpha_dev_chat-AbCdEf1234", log_type = "APPLICATION_LOGS" }
    }
  }

  expect_failures = [aws_cloudwatch_log_delivery_source.this]
}

run "source_listed_account_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
    sources = {
      chat-logs = { resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:222222222222:runtime/alpha_dev_chat-AbCdEf1234", log_type = "APPLICATION_LOGS" }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].resource_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:222222222222:runtime/alpha_dev_chat-AbCdEf1234"
    error_message = "A source in an account listed in allowed_account_ids must pass"
  }
}

# Same-account guard on CWL destinations

run "cwl_destination_other_account_rejected" {
  command = plan

  variables {
    destinations = {
      chat = { type = "CWL", resource_arn = "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat" }
    }
  }

  expect_failures = [aws_cloudwatch_log_delivery_destination.this]
}

run "cwl_destination_listed_account_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
    destinations = {
      chat = { type = "CWL", resource_arn = "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat" }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
    error_message = "A CWL destination in an account listed in allowed_account_ids must pass"
  }
}

run "cwl_destination_unlisted_account_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["333333333333"]
    destinations = {
      chat = { type = "CWL", resource_arn = "arn:aws:logs:ap-northeast-1:222222222222:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat" }
    }
  }

  expect_failures = [aws_cloudwatch_log_delivery_destination.this]
}

run "s3_and_xray_destinations_not_account_checked" {
  command = plan

  variables {
    destinations = {
      archive = { type = "S3", resource_arn = "arn:aws:s3:::alpha-dev-log-archive" }
      xray    = { type = "XRAY" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this) == 2
    error_message = "S3 bucket ARNs carry no account and XRAY has no ARN; both must pass"
  }
}

# allowed_account_ids format

run "allowed_account_ids_not_12_digits_rejected" {
  command = plan

  variables {
    allowed_account_ids = ["abc"]
  }

  expect_failures = [var.allowed_account_ids]
}

run "allowed_account_ids_12_digits_accepted" {
  command = plan

  variables {
    allowed_account_ids = ["222222222222"]
  }
}
