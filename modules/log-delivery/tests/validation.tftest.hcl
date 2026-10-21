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

run "log_type_of_other_services_passes" {
  command = plan

  variables {
    sources = {
      alb = {
        resource_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev-web/50dc6c495c0c9188"
        log_type     = "ALB_ACCESS_LOGS"
      }
      eks = {
        resource_arn = "arn:aws:eks:ap-northeast-1:111111111111:cluster/alpha-dev"
        log_type     = "AUTO_MODE_COMPUTE_LOGS"
      }
      cdn = {
        resource_arn = "arn:aws:cloudfront::111111111111:distribution/E2EXAMPLE12345"
        log_type     = "ACCESS_LOGS"
      }
    }
    deliveries = {}
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["alb"].log_type == "ALB_ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.this["eks"].log_type == "AUTO_MODE_COMPUTE_LOGS" && aws_cloudwatch_log_delivery_source.this["cdn"].log_type == "ACCESS_LOGS"
    error_message = "log_type must not be limited to AgentCore values"
  }
}

run "log_type_with_hyphen_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = "ALB-ACCESS-LOGS"
      }
    }
  }

  expect_failures = [var.sources]
}

run "log_type_empty_rejected" {
  command = plan

  variables {
    sources = {
      chat-logs = {
        resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
        log_type     = ""
      }
    }
  }

  expect_failures = [var.sources]
}

run "s3_bucket_source_passes" {
  command = plan

  variables {
    sources = {
      bucket = {
        resource_arn = "arn:aws:s3:::alpha-dev-assets"
        log_type     = "S3_SERVER_ACCESS_LOGS"
      }
    }
    deliveries = {}
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["bucket"].resource_arn == "arn:aws:s3:::alpha-dev-assets"
    error_message = "An S3 bucket ARN carries no account and must be accepted as a source"
  }
}

run "s3_object_arn_source_rejected" {
  command = plan

  variables {
    sources = {
      bucket = {
        resource_arn = "arn:aws:s3:::alpha-dev-assets/logs/*"
        log_type     = "S3_SERVER_ACCESS_LOGS"
      }
    }
    deliveries = {}
  }

  expect_failures = [var.sources]
}

run "destination_type_fh_passes" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "FH"
        resource_arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-logs"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-logs"
    error_message = "FH must send the delivery stream ARN as destination_resource_arn"
  }
}

run "fh_without_resource_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type = "FH"
      }
    }
  }

  expect_failures = [var.destinations]
}

run "fh_with_log_group_arn_rejected" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "FH"
        resource_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
      }
    }
  }

  expect_failures = [var.destinations]
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
