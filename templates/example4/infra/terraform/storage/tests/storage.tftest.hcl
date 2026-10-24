mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  tables = {
    ingest_state = {
      hash_key                    = "source_id"
      range_key                   = "ingested_at"
      attributes                  = { source_id = "S", ingested_at = "S" }
      ttl_attribute               = "expires_at"
      point_in_time_recovery_days = 7
    }
  }
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
    condition     = toset(keys(local.buckets)) == toset(["raw", "curated", "athena_results", "glue_assets"])
    error_message = "storage must create exactly the raw, curated, athena_results and glue_assets buckets"
  }

  assert {
    condition = (
      local.buckets["raw"].name == "example-dev-raw-111111111111" &&
      local.buckets["curated"].name == "example-dev-curated-111111111111" &&
      local.buckets["athena_results"].name == "example-dev-athena-results-111111111111" &&
      local.buckets["glue_assets"].name == "example-dev-glue-assets-111111111111"
    )
    error_message = "Bucket names must be <name_prefix>-<purpose>-<account id>"
  }
}

run "buckets_use_the_foundation_key" {
  command = plan

  assert {
    condition     = local.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Every bucket, the stream and the tables must use the shared key published by foundation"
  }
}

run "raw_bucket_expires_in_365_days_tiers_down_and_sends_events" {
  command = plan

  assert {
    condition     = local.buckets["raw"].expiration_days == 365 && !local.buckets["raw"].never_expire
    error_message = "raw must expire after 365 days"
  }

  assert {
    condition     = jsonencode(local.buckets["raw"].transitions) == jsonencode([{ days = 30, storage_class = "STANDARD_IA" }, { days = 90, storage_class = "GLACIER_IR" }])
    error_message = "raw must move to STANDARD_IA after 30 days and to GLACIER_IR after 90 days"
  }

  assert {
    condition     = local.buckets["raw"].eventbridge == true
    error_message = "raw must send S3 events to EventBridge: the Glue workflow starts from them (design D14)"
  }

  assert {
    condition     = local.buckets["raw"].versioning == null
    error_message = "raw must not keep object versions"
  }
}

run "curated_bucket_never_expires_and_is_versioned" {
  command = plan

  assert {
    condition     = local.buckets["curated"].never_expire == true && local.buckets["curated"].expiration_days == null
    error_message = "curated must never expire"
  }

  assert {
    condition     = local.buckets["curated"].versioning != null
    error_message = "curated must have versioning on"
  }

  assert {
    condition     = length(local.buckets["curated"].transitions) == 0 && local.buckets["curated"].eventbridge == false
    error_message = "curated has no tiering and sends no events"
  }
}

run "athena_results_bucket_expires_in_30_days" {
  command = plan

  assert {
    condition     = local.buckets["athena_results"].expiration_days == 30 && !local.buckets["athena_results"].never_expire && local.buckets["athena_results"].versioning == null
    error_message = "athena_results must expire after 30 days without versioning"
  }

  assert {
    condition     = length(local.buckets["athena_results"].transitions) == 0 && local.buckets["athena_results"].eventbridge == false
    error_message = "athena_results has no tiering and sends no events"
  }
}

run "glue_assets_bucket_expires_in_90_days_and_is_versioned" {
  command = plan

  assert {
    condition     = local.buckets["glue_assets"].expiration_days == 90 && !local.buckets["glue_assets"].never_expire
    error_message = "glue_assets must expire after 90 days"
  }

  assert {
    condition     = local.buckets["glue_assets"].versioning != null
    error_message = "glue_assets must have versioning on (job scripts)"
  }

  assert {
    condition     = length(local.buckets["glue_assets"].transitions) == 0 && local.buckets["glue_assets"].eventbridge == false
    error_message = "glue_assets has no tiering and sends no events"
  }
}

# Only raw may send events: any other bucket with eventbridge on would start workflows from its own objects.
run "only_raw_sends_eventbridge_events" {
  command = plan

  assert {
    condition     = [for k, b in local.buckets : k if b.eventbridge] == ["raw"]
    error_message = "raw is the only bucket with eventbridge = true"
  }
}

# The module call must pass every setting of the bucket spec; the module outputs are all a plan can see.
run "bucket_module_receives_the_whole_spec" {
  command = plan

  assert {
    condition = alltrue([
      for f in ["name", "kms_key_arn", "expiration_days", "never_expire", "transitions", "versioning", "eventbridge"] :
      length(regexall("(?m)^\\s*${f}\\s*=\\s*(each\\.value\\.${f}|local\\.kms_key_arn)\\s*$", file("${path.module}/buckets.tf"))) == 1
    ])
    error_message = "The bucket module call must take name, kms_key_arn, expiration_days, never_expire, transitions, versioning and eventbridge from the spec"
  }
}

run "two_glue_databases" {
  command = plan

  assert {
    condition     = local.databases["raw"].name == "example_dev_raw" && local.databases["curated"].name == "example_dev_curated" && length(local.databases) == 2
    error_message = "storage must create the raw and curated databases, named <project>_<env>_<layer> with underscores"
  }

  assert {
    condition     = toset(keys(module.catalog.database_arns)) == toset(["example_dev_raw", "example_dev_curated"])
    error_message = "glue-catalog must receive exactly the two databases"
  }
}

run "stream_is_one_shard_for_24_hours" {
  command = plan

  assert {
    condition     = local.stream == { name = "example-dev-events", mode = "PROVISIONED", shard_count = 1, retention_hours = 24 }
    error_message = "The stream must be provisioned with 1 shard and 24 hours of retention (design K11)"
  }
}

run "tables_are_named_and_keep_their_pitr_days" {
  command = plan

  assert {
    condition     = local.tables["ingest_state"].name == "example-dev-ingest-state" && local.tables["ingest_state"].point_in_time_recovery_days == 7
    error_message = "Table names are <name_prefix>-<key with hyphens>; the PITR days come from tfvars"
  }

  assert {
    condition     = toset(keys(module.table)) == toset(["ingest_state"])
    error_message = "One dynamodb-table module instance per entry of tables"
  }
}

run "table_pitr_defaults_to_35_days" {
  command = plan

  variables {
    tables = {
      t = { hash_key = "id", attributes = { id = "S" } }
    }
  }

  assert {
    condition     = local.tables["t"].point_in_time_recovery_days == 35
    error_message = "PITR defaults to the module maximum of 35 days"
  }
}

run "no_tables_by_default" {
  command = plan

  variables {
    tables = {}
  }

  assert {
    condition     = length(module.table) == 0 && length(local.table_alarms) == 0
    error_message = "An empty tables map must create no table and no table alarm"
  }
}

run "table_key_must_be_snake_case" {
  command = plan

  variables {
    tables = {
      "Bad-Key" = { hash_key = "id", attributes = { id = "S" } }
    }
  }

  expect_failures = [var.tables]
}

run "alarms_cover_the_stream_and_each_table" {
  command = plan

  assert {
    condition = toset(keys(local.alarms)) == toset([
      "stream_write_throughput_exceeded",
      "stream_read_throughput_exceeded",
      "stream_iterator_age",
      "table_ingest_state_write_throttled",
      "table_ingest_state_read_throttled",
    ])
    error_message = "storage must alarm on the stream (write and read throughput, iterator age) and on read and write throttling of each table"
  }

  assert {
    condition = (
      local.alarms["stream_iterator_age"].metric.namespace == "AWS/Kinesis" &&
      local.alarms["stream_iterator_age"].metric.metric_name == "GetRecords.IteratorAgeMilliseconds" &&
      local.alarms["stream_iterator_age"].metric.dimensions == { StreamName = "example-dev-events" } &&
      local.alarms["stream_write_throughput_exceeded"].metric.metric_name == "WriteProvisionedThroughputExceeded" &&
      local.alarms["stream_read_throughput_exceeded"].metric.metric_name == "ReadProvisionedThroughputExceeded"
    )
    error_message = "The stream alarms must use the AWS/Kinesis metrics of the stream"
  }

  assert {
    condition = (
      local.alarms["table_ingest_state_write_throttled"].metric.namespace == "AWS/DynamoDB" &&
      local.alarms["table_ingest_state_write_throttled"].metric.metric_name == "WriteThrottleEvents" &&
      local.alarms["table_ingest_state_write_throttled"].metric.dimensions == { TableName = "example-dev-ingest-state" } &&
      local.alarms["table_ingest_state_read_throttled"].metric.metric_name == "ReadThrottleEvents"
    )
    error_message = "The table alarms must use the AWS/DynamoDB throttle metrics of that table"
  }
}

run "publishes_exactly_the_storage_keys" {
  command = plan

  override_module {
    target = module.bucket["raw"]
    outputs = {
      bucket_name = "example-dev-raw-111111111111"
      arn         = "arn:aws:s3:::example-dev-raw-111111111111"
    }
  }

  override_module {
    target = module.bucket["curated"]
    outputs = {
      bucket_name = "example-dev-curated-111111111111"
      arn         = "arn:aws:s3:::example-dev-curated-111111111111"
    }
  }

  override_module {
    target = module.bucket["athena_results"]
    outputs = {
      bucket_name = "example-dev-athena-results-111111111111"
      arn         = "arn:aws:s3:::example-dev-athena-results-111111111111"
    }
  }

  override_module {
    target = module.bucket["glue_assets"]
    outputs = {
      bucket_name = "example-dev-glue-assets-111111111111"
      arn         = "arn:aws:s3:::example-dev-glue-assets-111111111111"
    }
  }

  override_module {
    target = module.stream
    outputs = {
      name = "example-dev-events"
      arn  = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events"
    }
  }

  override_module {
    target = module.table["ingest_state"]
    outputs = {
      table_name = "example-dev-ingest-state"
      arn        = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-ingest-state"
      stream_arn = null
    }
  }

  assert {
    condition = local.published_strings == {
      raw_bucket_arn             = "arn:aws:s3:::example-dev-raw-111111111111"
      raw_bucket_name            = "example-dev-raw-111111111111"
      curated_bucket_arn         = "arn:aws:s3:::example-dev-curated-111111111111"
      athena_results_bucket_arn  = "arn:aws:s3:::example-dev-athena-results-111111111111"
      athena_results_bucket_name = "example-dev-athena-results-111111111111"
      glue_assets_bucket_arn     = "arn:aws:s3:::example-dev-glue-assets-111111111111"
      raw_database_name          = "example_dev_raw"
      curated_database_name      = "example_dev_curated"
      stream_arn                 = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-events"
      table_ingest_state_arn     = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/example-dev-ingest-state"
    }
    error_message = "storage must publish exactly the String keys of design section 7.2, from the matching module outputs"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      raw_bucket_arn             = "/example/dev/storage/raw_bucket_arn"
      raw_bucket_name            = "/example/dev/storage/raw_bucket_name"
      curated_bucket_arn         = "/example/dev/storage/curated_bucket_arn"
      athena_results_bucket_arn  = "/example/dev/storage/athena_results_bucket_arn"
      athena_results_bucket_name = "/example/dev/storage/athena_results_bucket_name"
      glue_assets_bucket_arn     = "/example/dev/storage/glue_assets_bucket_arn"
      raw_database_name          = "/example/dev/storage/raw_database_name"
      curated_database_name      = "/example/dev/storage/curated_database_name"
      stream_arn                 = "/example/dev/storage/stream_arn"
      table_ingest_state_arn     = "/example/dev/storage/table_ingest_state_arn"
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
