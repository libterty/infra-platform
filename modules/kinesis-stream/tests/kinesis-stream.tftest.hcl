mock_provider "aws" {}

override_resource {
  target          = aws_kinesis_stream.this
  override_during = plan
  values = {
    arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"
  }
}

variables {
  name        = "alpha-dev-events"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "on_demand_is_the_default" {
  command = plan

  assert {
    condition     = one(aws_kinesis_stream.this.stream_mode_details).stream_mode == "ON_DEMAND"
    error_message = "mode must default to ON_DEMAND"
  }

  assert {
    condition     = aws_kinesis_stream.this.shard_count == null
    error_message = "On-demand streams must not carry a shard_count"
  }

  assert {
    condition     = aws_kinesis_stream.this.retention_period == 24
    error_message = "Retention must default to 24 hours"
  }

  assert {
    condition     = aws_kinesis_stream.this.name == "alpha-dev-events"
    error_message = "The stream name must be passed through"
  }
}

run "provisioned_with_shards" {
  command = plan

  variables {
    mode        = "PROVISIONED"
    shard_count = 1
  }

  assert {
    condition     = one(aws_kinesis_stream.this.stream_mode_details).stream_mode == "PROVISIONED"
    error_message = "mode must be passed through"
  }

  assert {
    condition     = aws_kinesis_stream.this.shard_count == 1
    error_message = "shard_count must be passed through"
  }
}

run "encryption_is_always_kms_with_the_given_key" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this.encryption_type == "KMS"
    error_message = "Encryption type must be KMS"
  }

  assert {
    condition     = aws_kinesis_stream.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The stream must use the key given as input"
  }
}

run "multi_region_key_arn_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  assert {
    condition     = aws_kinesis_stream.this.encryption_type == "KMS"
    error_message = "A multi-Region key ARN is a valid key"
  }
}

run "retention_boundaries_are_accepted" {
  command = plan

  variables {
    retention_hours = 8760
  }

  assert {
    condition     = aws_kinesis_stream.this.retention_period == 8760
    error_message = "8760 hours is the maximum and must be accepted"
  }
}

run "shard_level_metrics_are_passed_through" {
  command = plan

  variables {
    shard_level_metrics = ["IncomingBytes", "IteratorAgeMilliseconds"]
  }

  assert {
    condition     = aws_kinesis_stream.this.shard_level_metrics == toset(["IncomingBytes", "IteratorAgeMilliseconds"])
    error_message = "shard_level_metrics must be passed through"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_kinesis_stream.this.tags["Project"] == "alpha" && aws_kinesis_stream.this.tags["Name"] == "alpha-dev-events"
    error_message = "Name must be added to the given tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.name == "alpha-dev-events"
    error_message = "name output must be the stream name"
  }

  assert {
    condition     = output.arn == "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"
    error_message = "arn output must be the stream ARN"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "provisioned_without_shard_count_rejected" {
  command = plan

  variables {
    mode = "PROVISIONED"
  }

  expect_failures = [var.shard_count]
}

run "provisioned_with_zero_shards_rejected" {
  command = plan

  variables {
    mode        = "PROVISIONED"
    shard_count = 0
  }

  expect_failures = [var.shard_count]
}

run "on_demand_with_shard_count_rejected" {
  command = plan

  variables {
    mode        = "ON_DEMAND"
    shard_count = 1
  }

  expect_failures = [var.shard_count]
}

run "unknown_mode_rejected" {
  command = plan

  variables {
    mode = "SERVERLESS"
  }

  expect_failures = [var.mode]
}

run "retention_below_24_rejected" {
  command = plan

  variables {
    retention_hours = 23
  }

  expect_failures = [var.retention_hours]
}

run "retention_above_8760_rejected" {
  command = plan

  variables {
    retention_hours = 8761
  }

  expect_failures = [var.retention_hours]
}

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_id_without_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
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

run "unknown_shard_level_metric_rejected" {
  command = plan

  variables {
    shard_level_metrics = ["Bogus"]
  }

  expect_failures = [var.shard_level_metrics]
}

run "shard_level_metric_all_rejected" {
  command = plan

  variables {
    shard_level_metrics = ["ALL"]
  }

  expect_failures = [var.shard_level_metrics]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "alpha dev/events"
  }

  expect_failures = [var.name]
}
