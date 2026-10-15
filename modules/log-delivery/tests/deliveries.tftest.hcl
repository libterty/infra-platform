mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:delivery-destination:mock"
    }
  }
}

variables {
  name_prefix = "alpha-dev"

  sources = {
    chat-logs = {
      resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
      log_type     = "APPLICATION_LOGS"
    }
    chat-traces = {
      resource_arn = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/alpha_dev_chat-GhIjKl5678"
      log_type     = "TRACES"
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
    chat-traces = {
      source      = "chat-traces"
      destination = "xray"
    }
  }
}

run "empty_maps_create_nothing" {
  command = plan

  variables {
    sources      = {}
    destinations = {}
    deliveries   = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.this) == 0 && length(aws_cloudwatch_log_delivery_destination.this) == 0 && length(aws_cloudwatch_log_delivery.this) == 0
    error_message = "Empty maps must create no source, destination or delivery"
  }
}

run "one_resource_per_entry" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.this) == 2 && length(aws_cloudwatch_log_delivery_destination.this) == 2 && length(aws_cloudwatch_log_delivery.this) == 2
    error_message = "Each source, destination and delivery entry must create exactly one resource"
  }
}

run "source_attributes" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].name == "alpha-dev-chat-logs"
    error_message = "Source name must be <name_prefix>-<key>"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-traces"].log_type == "TRACES"
    error_message = "log_type must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].resource_arn == "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/alpha_dev_chat-AbCdEf1234"
    error_message = "resource_arn must be passed through"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].tags == tomap({ Name = "alpha-dev-chat-logs" })
    error_message = "Without tags input the only tag is Name"
  }
}

run "xray_destination_has_type_and_no_configuration" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["xray"].name == "alpha-dev-xray"
    error_message = "Destination name must be <name_prefix>-<key>"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["xray"].delivery_destination_type == "XRAY"
    error_message = "XRAY destination must set delivery_destination_type = XRAY"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this["xray"].delivery_destination_configuration) == 0
    error_message = "XRAY destination must not send delivery_destination_configuration"
  }
}

run "cwl_destination_has_only_resource_arn" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration) == 1
    error_message = "CWL destination must send one delivery_destination_configuration block"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/vendedlogs/bedrock-agentcore/alpha-dev-chat"
    error_message = "CWL destination must point at the log group ARN"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["chat"].output_format == null
    error_message = "output_format must be left to the service default"
  }
}

run "s3_destination_has_only_resource_arn" {
  command = plan

  variables {
    destinations = {
      chat = {
        type         = "S3"
        resource_arn = "arn:aws:s3:::alpha-dev-logs-111111111111"
      }
      xray = {
        type = "XRAY"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["chat"].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:s3:::alpha-dev-logs-111111111111"
    error_message = "S3 destination must point at the bucket ARN"
  }
}

run "delivery_wiring" {
  command = apply

  override_resource {
    target = aws_cloudwatch_log_delivery_destination.this["chat"]
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:delivery-destination:alpha-dev-chat"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_delivery_destination.this["xray"]
    values = {
      arn = "arn:aws:logs:ap-northeast-1:111111111111:delivery-destination:alpha-dev-xray"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["chat-logs"].delivery_source_name == "alpha-dev-chat-logs"
    error_message = "chat-logs delivery must use the chat-logs source"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["chat-traces"].delivery_source_name == "alpha-dev-chat-traces"
    error_message = "chat-traces delivery must use the chat-traces source"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["chat-logs"].delivery_destination_arn == "arn:aws:logs:ap-northeast-1:111111111111:delivery-destination:alpha-dev-chat"
    error_message = "chat-logs delivery must use the chat destination"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["chat-traces"].delivery_destination_arn == "arn:aws:logs:ap-northeast-1:111111111111:delivery-destination:alpha-dev-xray"
    error_message = "chat-traces delivery must use the xray destination"
  }

  assert {
    condition     = terraform_data.source_arn["chat-traces"].output == aws_cloudwatch_log_delivery_source.this["chat-traces"].resource_arn
    error_message = "The replacement trigger of a delivery must track the resource_arn of its own source"
  }

}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["chat-logs"].tags == tomap({ Project = "alpha", Name = "alpha-dev-chat-logs" })
    error_message = "Source tags must keep input tags and add Name"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this["xray"].tags == tomap({ Project = "alpha", Name = "alpha-dev-xray" })
    error_message = "Destination tags must keep input tags and add Name"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this["chat-logs"].tags == tomap({ Project = "alpha" })
    error_message = "Delivery has no name, so it carries the input tags only"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.source_names["chat-logs"] == "alpha-dev-chat-logs" && output.source_names["chat-traces"] == "alpha-dev-chat-traces" && length(output.source_names) == 2
    error_message = "source_names must map each source key to its name"
  }

  assert {
    condition     = output.destination_arns["xray"] == aws_cloudwatch_log_delivery_destination.this["xray"].arn && length(output.destination_arns) == 2
    error_message = "destination_arns must map each destination key to its ARN"
  }

  assert {
    condition     = output.delivery_ids["chat-logs"] == aws_cloudwatch_log_delivery.this["chat-logs"].id && length(output.delivery_ids) == 2
    error_message = "delivery_ids must map each delivery key to its id"
  }
}
