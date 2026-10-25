mock_provider "aws" {}

override_resource {
  target          = aws_sqs_queue.this
  override_during = plan
  values = {
    arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
    url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved"
  }
}

override_resource {
  target          = aws_sqs_queue.dlq
  override_during = plan
  values = {
    arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved-dlq"
    url = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved-dlq"
  }
}

variables {
  name        = "alpha-dev-model-approved"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "standard_queue_defaults" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.name == "alpha-dev-model-approved" && aws_sqs_queue.dlq.name == "alpha-dev-model-approved-dlq"
    error_message = "The queue keeps the given name and the DLQ adds -dlq"
  }

  assert {
    condition     = aws_sqs_queue.this.fifo_queue == false && aws_sqs_queue.dlq.fifo_queue == false
    error_message = "Both queues must be standard queues by default"
  }

  assert {
    condition     = aws_sqs_queue.this.visibility_timeout_seconds == 30 && aws_sqs_queue.this.message_retention_seconds == 345600
    error_message = "Visibility timeout must default to 30 seconds and retention to 4 days"
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600
    error_message = "The DLQ must keep messages for 14 days by default"
  }
}

run "both_queues_are_encrypted_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The main queue must use the given CMK"
  }

  assert {
    condition     = aws_sqs_queue.dlq.kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The DLQ must use the given CMK"
  }
}

run "redrive_to_the_dlq" {
  command = plan

  assert {
    condition     = aws_sqs_queue_redrive_policy.this.queue_url == "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved"
    error_message = "The redrive policy belongs to the main queue"
  }

  assert {
    condition = jsondecode(aws_sqs_queue_redrive_policy.this.redrive_policy) == {
      deadLetterTargetArn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved-dlq"
      maxReceiveCount     = 5
    }
    error_message = "Messages must move to the DLQ after 5 receives"
  }

  assert {
    condition     = aws_sqs_queue_redrive_allow_policy.dlq.queue_url == "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved-dlq"
    error_message = "The redrive allow policy belongs to the DLQ"
  }

  assert {
    condition = jsondecode(aws_sqs_queue_redrive_allow_policy.dlq.redrive_allow_policy) == {
      redrivePermission = "byQueue"
      sourceQueueArns   = ["arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"]
    }
    error_message = "Only the main queue may use the DLQ"
  }
}

run "custom_receive_count_and_retention" {
  command = plan

  variables {
    max_receive_count          = 10
    visibility_timeout_seconds = 300
    message_retention_seconds  = 1209600
    dlq_retention_seconds      = 60
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this.redrive_policy).maxReceiveCount == 10
    error_message = "max_receive_count must be passed through"
  }

  assert {
    condition     = aws_sqs_queue.this.visibility_timeout_seconds == 300 && aws_sqs_queue.this.message_retention_seconds == 1209600 && aws_sqs_queue.dlq.message_retention_seconds == 60
    error_message = "Timeouts and retention must be passed through"
  }
}

run "no_queue_policy_without_sources" {
  command = plan

  assert {
    condition     = length(aws_sqs_queue_policy.this) == 0
    error_message = "No queue policy may be created when allowed_source_arns is empty"
  }
}

run "queue_policy_allows_only_the_given_rules" {
  command = plan

  variables {
    allowed_source_arns = [
      "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-model-approved",
      "arn:aws:events:ap-northeast-1:111111111111:rule/custom-bus/alpha-dev-other",
    ]
  }

  assert {
    condition     = aws_sqs_queue_policy.this[0].queue_url == "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved"
    error_message = "The queue policy belongs to the main queue"
  }

  assert {
    condition = jsondecode(aws_sqs_queue_policy.this[0].policy).Statement == [{
      Sid       = "AllowEventBridgeRules"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = [
            "arn:aws:events:ap-northeast-1:111111111111:rule/alpha-dev-model-approved",
            "arn:aws:events:ap-northeast-1:111111111111:rule/custom-bus/alpha-dev-other",
          ]
        }
      }
    }]
    error_message = "Only events.amazonaws.com may send, only to this queue, only from the given rules"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_sqs_queue_policy.this[0].policy).Statement : s.Resource != "*" && s.Principal != "*"])
    error_message = "The queue policy must not use a wildcard resource or principal"
  }
}

run "fifo_queue_and_fifo_dlq" {
  command = plan

  variables {
    fifo = true
  }

  assert {
    condition     = aws_sqs_queue.this.name == "alpha-dev-model-approved.fifo" && aws_sqs_queue.dlq.name == "alpha-dev-model-approved-dlq.fifo"
    error_message = "FIFO queue names must end with .fifo"
  }

  assert {
    condition     = aws_sqs_queue.this.fifo_queue == true && aws_sqs_queue.dlq.fifo_queue == true
    error_message = "The DLQ of a FIFO queue must be a FIFO queue too"
  }

  assert {
    condition     = aws_sqs_queue.this.content_based_deduplication == true
    error_message = "FIFO queues use content-based deduplication"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Project"] == "alpha" && aws_sqs_queue.this.tags["Name"] == "alpha-dev-model-approved"
    error_message = "Name must be added to the main queue tags"
  }

  assert {
    condition     = aws_sqs_queue.dlq.tags["Project"] == "alpha" && aws_sqs_queue.dlq.tags["Name"] == "alpha-dev-model-approved-dlq"
    error_message = "Name must be added to the DLQ tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.queue_arn == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved"
    error_message = "queue_arn output must be the main queue ARN"
  }

  assert {
    condition     = output.queue_url == "https://sqs.ap-northeast-1.amazonaws.com/111111111111/alpha-dev-model-approved"
    error_message = "queue_url output must be the main queue URL"
  }

  assert {
    condition     = output.queue_name == "alpha-dev-model-approved"
    error_message = "queue_name output must be the main queue name"
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-model-approved-dlq"
    error_message = "dlq_arn output must be the DLQ ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "retention_below_60_rejected" {
  command = plan

  variables {
    message_retention_seconds = 59
  }

  expect_failures = [var.message_retention_seconds]
}

run "retention_above_14_days_rejected" {
  command = plan

  variables {
    message_retention_seconds = 1209601
  }

  expect_failures = [var.message_retention_seconds]
}

run "dlq_retention_out_of_range_rejected" {
  command = plan

  variables {
    dlq_retention_seconds = 1209601
  }

  expect_failures = [var.dlq_retention_seconds]
}

run "receive_count_zero_rejected" {
  command = plan

  variables {
    max_receive_count = 0
  }

  expect_failures = [var.max_receive_count]
}

run "receive_count_above_1000_rejected" {
  command = plan

  variables {
    max_receive_count = 1001
  }

  expect_failures = [var.max_receive_count]
}

run "visibility_timeout_above_12_hours_rejected" {
  command = plan

  variables {
    visibility_timeout_seconds = 43201
  }

  expect_failures = [var.visibility_timeout_seconds]
}

run "source_arn_not_an_events_rule_rejected" {
  command = plan

  variables {
    allowed_source_arns = ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alerts"]
  }

  expect_failures = [var.allowed_source_arns]
}

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "name_with_fifo_suffix_rejected" {
  command = plan

  variables {
    name = "alpha-dev-model-approved.fifo"
  }

  expect_failures = [var.name]
}

run "name_too_long_rejected" {
  command = plan

  variables {
    name = "a234567890a234567890a234567890a234567890a234567890a234567890a234567890ab"
  }

  expect_failures = [var.name]
}
