mock_provider "aws" {}

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
    xray = {
      type = "XRAY"
    }
  }

  deliveries = {
    chat-logs = {
      source      = "chat-logs"
      destination = "chat"
    }
  }
}

run "log_type_access_logs_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = "ACCESS_LOGS"
      }
    }
  }

  expect_failures = [var.sources]
}

run "log_type_usage_logs_passes" {
  command = plan

  variables {
    sources = {
      chat-logs = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = "USAGE_LOGS"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].log_type == "USAGE_LOGS"
    error_message = "USAGE_LOGS is an accepted log_type"
  }
}

run "destination_type_firehose_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "FIREHOSE"
        resource_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-logs"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "xray_with_resource_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "CWL"
        resource_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
      }
      xray = {
        type         = "XRAY"
        resource_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:aws/spans"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "xray_without_resource_arn_passes" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["xray"].delivery_destination_type == "XRAY"
    error_message = "XRAY without resource_arn must be accepted"
  }
}

run "cwl_without_resource_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type = "CWL"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "cwl_with_bucket_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "CWL"
        resource_arn = "arn:aws:s3:::alpha-dev-logs-111111111111"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "cwl_with_log_group_arn_passes" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration) == 1
    error_message = "CWL with a log group ARN must be accepted"
  }
}

run "s3_without_resource_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type = "S3"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "s3_with_log_group_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "S3"
        resource_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "s3_with_bucket_arn_passes" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "S3"
        resource_arn = "arn:aws:s3:::alpha-dev-logs-111111111111"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration) == 1
    error_message = "S3 with a bucket ARN must be accepted"
  }
}

run "delivery_unknown_source_rejected" {
  command = plan

  variables {
    deliveries = {
      chat-logs = {
        source      = "missing"
        destination = "chat"
      }
    }
  }

  expect_failures = [var.deliveries]
}

run "delivery_unknown_destination_rejected" {
  command = plan

  variables {
    deliveries = {
      chat-logs = {
        source      = "chat-logs"
        destination = "missing"
      }
    }
  }

  expect_failures = [var.deliveries]
}

run "delivery_duplicate_pair_rejected" {
  command = plan

  variables {
    deliveries = {
      first = {
        source      = "chat-logs"
        destination = "chat"
      }
      second = {
        source      = "chat-logs"
        destination = "chat"
      }
    }
  }

  expect_failures = [var.deliveries]
}

run "delivery_same_source_two_destinations_passes" {
  command = plan

  variables {
    deliveries = {
      to-logs = {
        source      = "chat-logs"
        destination = "chat"
      }
      to-xray = {
        source      = "chat-logs"
        destination = "xray"
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery.this) == 2
    error_message = "One source may feed two different destinations"
  }
}

run "source_name_61_chars_rejected" {
  command = plan

  variables {
    sources = {
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = "APPLICATION_LOGS"
      }
    }
    deliveries = {}
  }

  expect_failures = [var.sources]
}

run "source_name_60_chars_passes" {
  command = plan

  variables {
    sources = {
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = "APPLICATION_LOGS"
      }
    }
    deliveries = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.this["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].name) == 60
    error_message = "A 60-character source name must be accepted"
  }
}

run "destination_name_61_chars_rejected" {
  command = plan

  variables {
    destinations = {
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
        type = "XRAY"
      }
    }
    deliveries = {}
  }

  expect_failures = [var.destinations]
}

run "destination_name_60_chars_passes" {
  command = plan

  variables {
    destinations = {
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
        type = "XRAY"
      }
    }
    deliveries = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].name) == 60
    error_message = "A 60-character destination name must be accepted"
  }
}
