mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

run "reads_only_the_foundation_keys" {
  command = plan

  assert {
    condition     = local.ssm_input_strings == { kms_key_arn = "foundation/kms_key_arn", alarm_topic_arn = "foundation/alarm_topic_arn" } && local.ssm_input_lists == {}
    error_message = "storage must read the shared key and the alarm topic from foundation and nothing else"
  }
}

run "four_buckets_named_after_prefix_and_account" {
  command = plan

  assert {
    condition     = toset(keys(local.buckets)) == toset(["telemetry", "greengrass_artifacts", "ota", "ml"])
    error_message = "storage must create exactly the telemetry, greengrass_artifacts, ota and ml buckets (design section 7.1)"
  }

  assert {
    condition = (
      local.buckets["telemetry"].name == "example-dev-telemetry-111111111111" &&
      local.buckets["greengrass_artifacts"].name == "example-dev-greengrass-artifacts-111111111111" &&
      local.buckets["ota"].name == "example-dev-ota-artifacts-111111111111" &&
      local.buckets["ml"].name == "example-dev-ml-artifacts-111111111111"
    )
    error_message = "Bucket names must be <name_prefix>-<purpose>-<account id>"
  }
}

run "everything_uses_the_foundation_key" {
  command = plan

  assert {
    condition     = local.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Every bucket, the stream and the queues must use the shared key published by foundation"
  }

  assert {
    condition     = alltrue([for f in ["buckets.tf", "stream.tf", "queues.tf"] : length(regexall("(?m)^\\s*kms_key_arn\\s*=\\s*local\\.kms_key_arn\\s*$", file("${path.module}/${f}"))) == 1])
    error_message = "The bucket, stream and queue module calls must pass the shared key"
  }
}

run "telemetry_bucket_expires_in_365_days_and_tiers_down" {
  command = plan

  assert {
    condition     = local.buckets["telemetry"].expiration_days == 365 && !local.buckets["telemetry"].never_expire && local.buckets["telemetry"].versioning == null
    error_message = "telemetry must expire after 365 days and is not versioned"
  }

  assert {
    condition     = jsonencode(local.buckets["telemetry"].transitions) == jsonencode([{ days = 30, storage_class = "STANDARD_IA" }, { days = 90, storage_class = "GLACIER_IR" }])
    error_message = "telemetry must move to STANDARD_IA after 30 days and to GLACIER_IR after 90 days"
  }
}

# Artifacts are what devices and endpoints run: they never expire and old versions stay 30 days for rollback mistakes.
run "artifact_buckets_never_expire_and_are_versioned" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["greengrass_artifacts", "ota", "ml"] :
      local.buckets[k].never_expire && local.buckets[k].expiration_days == null && local.buckets[k].transitions == [] &&
      local.buckets[k].versioning == { noncurrent_expiration_days = 30 }
    ])
    error_message = "greengrass_artifacts, ota and ml must never expire and keep noncurrent versions for 30 days"
  }
}

run "bucket_module_receives_the_whole_spec" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "kms_key_arn", "expiration_days", "never_expire", "transitions", "versioning"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*(each\\.value\\.${f}|local\\.kms_key_arn)\\s*$", file("${path.module}/buckets.tf"))) == 1
    ])
    error_message = "The bucket module call must take name, kms_key_arn, expiration_days, never_expire, transitions and versioning from the spec"
  }
}

run "stream_is_one_shard_for_24_hours" {
  command = plan

  assert {
    condition     = local.stream.name == "example-dev-telemetry" && local.stream.mode == "PROVISIONED" && local.stream.shard_count == 1 && local.stream.retention_hours == 24
    error_message = "The stream must be example-dev-telemetry, provisioned with one shard and 24 hours of retention (design section 7.5)"
  }
}

run "two_queues_with_their_names" {
  command = plan

  assert {
    condition     = toset(keys(local.queues)) == toset(["rule_errors", "model_approved"])
    error_message = "storage must create exactly the rule_errors and model_approved queues"
  }

  assert {
    condition     = local.queues["rule_errors"].name == "example-dev-rule-errors" && local.queues["model_approved"].name == "example-dev-model-approved"
    error_message = "Queue names must be <name_prefix>-rule-errors and <name_prefix>-model-approved"
  }
}

# IoT rules write with a role, so rule-errors needs no queue policy (design K23).
run "rule_errors_has_no_queue_policy" {
  command = plan

  assert {
    condition     = local.queues["rule_errors"].allowed_source_arns == []
    error_message = "rule-errors must not have a queue policy: the IoT rule role writes to it"
  }
}

# Naming contract with the ml stack (design K22, K23): the rule does not exist yet, so its ARN comes from the name.
run "model_approved_allows_only_the_single_ml_rule" {
  command = plan

  assert {
    condition     = local.model_approved_rule_arn == "arn:aws:events:ap-northeast-1:111111111111:rule/example-dev-model-approved"
    error_message = "The EventBridge rule ARN must come from the naming rule <name_prefix>-model-approved on the default bus"
  }

  assert {
    condition     = local.queues["model_approved"].allowed_source_arns == ["arn:aws:events:ap-northeast-1:111111111111:rule/example-dev-model-approved"]
    error_message = "model-approved must accept messages from exactly the ml stack's rule"
  }

  assert {
    condition     = !strcontains(local.model_approved_rule_arn, "*") && !strcontains(local.model_approved_rule_arn, "?")
    error_message = "The rule ARN must not contain a wildcard"
  }
}

run "naming_rule_for_sit" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.model_approved_rule_arn == "arn:aws:events:ap-northeast-1:222222222222:rule/example-sit-model-approved"
    error_message = "The rule ARN must follow the env and account"
  }
}

run "queue_module_receives_the_whole_spec" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "kms_key_arn", "allowed_source_arns"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*(each\\.value\\.${f}|local\\.kms_key_arn)\\s*$", file("${path.module}/queues.tf"))) == 1
    ])
    error_message = "The queue module call must take name, kms_key_arn and allowed_source_arns from the spec"
  }
}

run "alarms_cover_the_stream_and_the_queues" {
  command = plan

  assert {
    condition = toset(keys(local.alarms)) == toset([
      "stream_write_throughput_exceeded",
      "stream_read_throughput_exceeded",
      "stream_iterator_age",
      "rule_errors_received",
      "rule_errors_dlq_not_empty",
      "model_approved_oldest_message_age",
      "model_approved_dlq_not_empty",
    ])
    error_message = "storage must alarm on the stream, on rule errors, on an unconsumed model approval and on both DLQs"
  }

  assert {
    condition = (
      local.alarms["stream_iterator_age"].metric.namespace == "AWS/Kinesis" &&
      local.alarms["stream_iterator_age"].metric.metric_name == "GetRecords.IteratorAgeMilliseconds" &&
      local.alarms["stream_iterator_age"].metric.dimensions == { StreamName = "example-dev-telemetry" }
    )
    error_message = "The stream alarms must use the AWS/Kinesis metrics of the stream"
  }

  assert {
    condition = (
      local.alarms["rule_errors_received"].metric.namespace == "AWS/SQS" &&
      local.alarms["rule_errors_received"].metric.metric_name == "ApproximateNumberOfMessagesVisible" &&
      local.alarms["rule_errors_received"].metric.dimensions == { QueueName = "example-dev-rule-errors" } &&
      local.alarms["rule_errors_received"].threshold == 1 &&
      local.alarms["rule_errors_dlq_not_empty"].metric.dimensions == { QueueName = "example-dev-rule-errors-dlq" } &&
      local.alarms["model_approved_dlq_not_empty"].metric.dimensions == { QueueName = "example-dev-model-approved-dlq" } &&
      local.alarms["model_approved_oldest_message_age"].metric.metric_name == "ApproximateAgeOfOldestMessage" &&
      local.alarms["model_approved_oldest_message_age"].metric.dimensions == { QueueName = "example-dev-model-approved" } &&
      local.alarms["model_approved_oldest_message_age"].threshold == 86400
    )
    error_message = "The queue alarms must use the AWS/SQS metrics of the main queues and their -dlq queues"
  }

  assert {
    condition     = tolist(local.alarm_topic_arns) == tolist(["arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"])
    error_message = "Alarms must notify the foundation alarm topic"
  }
}

run "publishes_exactly_the_storage_keys" {
  command = plan

  override_module {
    target  = module.bucket["telemetry"]
    outputs = { bucket_name = "example-dev-telemetry-111111111111", arn = "arn:aws:s3:::example-dev-telemetry-111111111111" }
  }

  override_module {
    target  = module.bucket["greengrass_artifacts"]
    outputs = { bucket_name = "example-dev-greengrass-artifacts-111111111111", arn = "arn:aws:s3:::example-dev-greengrass-artifacts-111111111111" }
  }

  override_module {
    target  = module.bucket["ota"]
    outputs = { bucket_name = "example-dev-ota-artifacts-111111111111", arn = "arn:aws:s3:::example-dev-ota-artifacts-111111111111" }
  }

  override_module {
    target  = module.bucket["ml"]
    outputs = { bucket_name = "example-dev-ml-artifacts-111111111111", arn = "arn:aws:s3:::example-dev-ml-artifacts-111111111111" }
  }

  override_module {
    target  = module.stream
    outputs = { arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry", name = "example-dev-telemetry" }
  }

  override_module {
    target = module.queue["rule_errors"]
    outputs = {
      queue_arn  = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors"
      queue_url  = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/example-dev-rule-errors"
      queue_name = "example-dev-rule-errors"
      dlq_arn    = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors-dlq"
    }
  }

  override_module {
    target = module.queue["model_approved"]
    outputs = {
      queue_arn  = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved"
      queue_url  = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/example-dev-model-approved"
      queue_name = "example-dev-model-approved"
      dlq_arn    = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved-dlq"
    }
  }

  assert {
    condition = local.published_strings == {
      telemetry_bucket_arn             = "arn:aws:s3:::example-dev-telemetry-111111111111"
      greengrass_artifacts_bucket_arn  = "arn:aws:s3:::example-dev-greengrass-artifacts-111111111111"
      greengrass_artifacts_bucket_name = "example-dev-greengrass-artifacts-111111111111"
      ota_bucket_arn                   = "arn:aws:s3:::example-dev-ota-artifacts-111111111111"
      ml_bucket_arn                    = "arn:aws:s3:::example-dev-ml-artifacts-111111111111"
      ml_bucket_name                   = "example-dev-ml-artifacts-111111111111"
      stream_arn                       = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry"
      rule_errors_queue_arn            = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors"
      rule_errors_queue_url            = "https://sqs.ap-northeast-1.amazonaws.com/111111111111/example-dev-rule-errors"
      model_approved_queue_arn         = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved"
    }
    error_message = "storage must publish exactly the ten String keys of design section 7.2, from the matching modules"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      telemetry_bucket_arn             = "/example/dev/storage/telemetry_bucket_arn"
      greengrass_artifacts_bucket_arn  = "/example/dev/storage/greengrass_artifacts_bucket_arn"
      greengrass_artifacts_bucket_name = "/example/dev/storage/greengrass_artifacts_bucket_name"
      ota_bucket_arn                   = "/example/dev/storage/ota_bucket_arn"
      ml_bucket_arn                    = "/example/dev/storage/ml_bucket_arn"
      ml_bucket_name                   = "/example/dev/storage/ml_bucket_name"
      stream_arn                       = "/example/dev/storage/stream_arn"
      rule_errors_queue_arn            = "/example/dev/storage/rule_errors_queue_arn"
      rule_errors_queue_url            = "/example/dev/storage/rule_errors_queue_url"
      model_approved_queue_arn         = "/example/dev/storage/model_approved_queue_arn"
    }
    error_message = "ssm-publish must write the contract keys under the storage stack path"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "example-dev" && local.ssm_prefix == "/example/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
