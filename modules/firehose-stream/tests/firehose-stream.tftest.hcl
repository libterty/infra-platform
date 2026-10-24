mock_provider "aws" {}

override_resource {
  target          = aws_kinesis_firehose_delivery_stream.this
  override_during = plan
  values = {
    arn = "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-raw"
  }
}

variables {
  name        = "alpha-dev-raw"
  role_arn    = "arn:aws:iam::111111111111:role/alpha-dev-firehose"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"

  s3 = {
    bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
  }
}

# ---- positive: source and server-side encryption ---------------------------------------------------------------

run "kinesis_source_to_s3_has_no_server_side_encryption" {
  command = plan

  variables {
    source_stream_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.kinesis_source_configuration).kinesis_stream_arn == "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events" &&
      one(aws_kinesis_firehose_delivery_stream.this.kinesis_source_configuration).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-firehose"
    )
    error_message = "A Kinesis source must be read with the given stream ARN and the delivery role"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.server_side_encryption) == 0
    error_message = "SSE only works for Direct PUT; a Kinesis-sourced stream must not carry server_side_encryption (encryption is on the source stream)"
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.this.destination == "extended_s3"
    error_message = "Without an opensearch input the destination must be extended_s3"
  }
}

run "direct_put_to_s3_encrypts_with_the_given_key" {
  command = plan

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.server_side_encryption).enabled == true &&
      one(aws_kinesis_firehose_delivery_stream.this.server_side_encryption).key_type == "CUSTOMER_MANAGED_CMK" &&
      one(aws_kinesis_firehose_delivery_stream.this.server_side_encryption).key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    )
    error_message = "A Direct PUT stream must be encrypted at rest with the given customer managed key"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.kinesis_source_configuration) == 0
    error_message = "A Direct PUT stream must not have a Kinesis source block"
  }
}

# ---- positive: S3 destination ----------------------------------------------------------------------------------

run "s3_destination_gzip_prefixes_and_kms" {
  command = plan

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).compression_format == "GZIP"
    error_message = "Compression must default to GZIP"
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).bucket_arn == "arn:aws:s3:::alpha-dev-raw" &&
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-firehose"
    )
    error_message = "The bucket and the delivery role must be passed through"
  }

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).prefix == "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_message = "The time prefix must be passed through"
  }

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).error_output_prefix == "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_message = "The error output prefix must be passed through"
  }

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Objects written to S3 must be encrypted with the given key"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration) == 0
    error_message = "An S3 destination must not carry an opensearch_configuration"
  }
}

run "s3_buffering_defaults_match_the_event_trigger_design" {
  command = plan

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).buffering_interval == 900 &&
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).buffering_size == 64
    )
    error_message = "Buffering must default to 900 seconds and 64 MiB"
  }
}

run "s3_buffering_is_overridable" {
  command = plan

  variables {
    s3 = {
      bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
      prefix              = "raw/"
      buffering_interval  = 60
      buffering_size      = 5
      compression         = "UNCOMPRESSED"
      error_output_prefix = null
    }
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).buffering_interval == 60 &&
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).buffering_size == 5 &&
      one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).compression_format == "UNCOMPRESSED"
    )
    error_message = "Buffering and compression overrides must be passed through"
  }
}

run "plain_prefix_may_leave_error_prefix_unset" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw"
      prefix     = "raw/"
    }
  }

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).error_output_prefix == null
    error_message = "A prefix without expressions may leave error_output_prefix unset (AWS derives it)"
  }
}

# ---- positive: CloudWatch logging ------------------------------------------------------------------------------

run "log_group_is_encrypted_and_named_after_the_stream" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/kinesisfirehose/alpha-dev-raw"
    error_message = "The log group must be /aws/kinesisfirehose/<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The log group must be encrypted with the given key"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Log retention must default to 30 days"
  }

  assert {
    condition     = aws_cloudwatch_log_stream.destination.name == "DestinationDelivery" && aws_cloudwatch_log_stream.destination.log_group_name == "/aws/kinesisfirehose/alpha-dev-raw"
    error_message = "The DestinationDelivery log stream must exist in the log group"
  }
}

run "s3_destination_logging_is_always_on" {
  command = plan

  assert {
    condition = (
      one(one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).cloudwatch_logging_options).enabled == true &&
      one(one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).cloudwatch_logging_options).log_group_name == "/aws/kinesisfirehose/alpha-dev-raw" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration).cloudwatch_logging_options).log_stream_name == "DestinationDelivery"
    )
    error_message = "Delivery logging must be enabled and point at the module's log group and stream"
  }
}

run "log_retention_is_overridable" {
  command = plan

  variables {
    log_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90
    error_message = "log_retention_days must be passed through"
  }
}

run "name_tag_is_added_and_tags_are_kept" {
  command = plan

  variables {
    tags = {
      Project = "alpha"
    }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.this.tags["Name"] == "alpha-dev-raw" && aws_kinesis_firehose_delivery_stream.this.tags["Project"] == "alpha"
    error_message = "The stream must carry the given tags plus Name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Name"] == "/aws/kinesisfirehose/alpha-dev-raw" && aws_cloudwatch_log_group.this.tags["Project"] == "alpha"
    error_message = "The log group must carry the given tags plus Name"
  }
}

run "outputs_expose_name_arn_and_log_group" {
  command = plan

  assert {
    condition     = output.name == "alpha-dev-raw" && output.log_group_name == "/aws/kinesisfirehose/alpha-dev-raw"
    error_message = "name and log_group_name outputs must match the resources"
  }

  assert {
    condition     = output.arn == "arn:aws:firehose:ap-northeast-1:111111111111:deliverystream/alpha-dev-raw"
    error_message = "arn output must be the delivery stream ARN"
  }
}

# ---- positive: OpenSearch destination --------------------------------------------------------------------------

run "opensearch_destination_in_vpc_with_failed_only_backup" {
  command = plan

  variables {
    source_stream_arn = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/alpha-dev-events"

    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw"
      prefix     = "errors/"
    }

    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "alpha-dev-events"
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition     = aws_kinesis_firehose_delivery_stream.this.destination == "opensearch"
    error_message = "An opensearch input must switch the destination to opensearch"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.extended_s3_configuration) == 0
    error_message = "An OpenSearch destination must not carry an extended_s3_configuration"
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).domain_arn == "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search" &&
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).index_name == "alpha-dev-events" &&
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-firehose"
    )
    error_message = "domain, index and role must be passed through"
  }

  assert {
    condition = (
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).vpc_config).role_arn == "arn:aws:iam::111111111111:role/alpha-dev-firehose" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).vpc_config).subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]) &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).vpc_config).security_group_ids == toset(["sg-0123456789abcdef0"])
    )
    error_message = "VPC config must use the delivery role, the given subnets and the given security groups"
  }

  assert {
    condition     = one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_backup_mode == "FailedDocumentsOnly"
    error_message = "S3 backup must only keep failed documents"
  }

  assert {
    condition = (
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).bucket_arn == "arn:aws:s3:::alpha-dev-raw" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).prefix == "errors/" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).compression_format == "GZIP"
    )
    error_message = "The S3 backup must use the given bucket and prefix, GZIP, and the given KMS key"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.server_side_encryption) == 0
    error_message = "A Kinesis-sourced OpenSearch stream must not carry server_side_encryption"
  }
}

run "opensearch_defaults_and_logging" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw"
      prefix     = "errors/"
    }

    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "alpha-dev-events"
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).index_rotation_period == "OneDay" &&
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).retry_duration == 300
    )
    error_message = "Rotation must default to OneDay and retry to 300 seconds"
  }

  assert {
    condition = (
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).cloudwatch_logging_options).enabled == true &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).cloudwatch_logging_options).log_group_name == "/aws/kinesisfirehose/alpha-dev-raw" &&
      one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).cloudwatch_logging_options).log_stream_name == "DestinationDelivery"
    )
    error_message = "OpenSearch delivery logging must be enabled"
  }

  assert {
    condition = (
      one(one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).cloudwatch_logging_options).enabled == true &&
      one(one(one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).s3_configuration).cloudwatch_logging_options).log_stream_name == "BackupDelivery"
    )
    error_message = "S3 backup logging must be enabled on the BackupDelivery stream"
  }

  assert {
    condition     = length(aws_cloudwatch_log_stream.backup) == 1 && aws_cloudwatch_log_stream.backup[0].name == "BackupDelivery"
    error_message = "The BackupDelivery log stream must exist for an OpenSearch destination"
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this.server_side_encryption) == 1
    error_message = "A Direct PUT stream must be encrypted even when the destination is OpenSearch"
  }
}

run "opensearch_overrides" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw"
      prefix     = "errors/"
    }

    opensearch = {
      domain_arn            = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name            = "alpha-dev-events"
      index_rotation_period = "OneWeek"
      retry_seconds         = 0
      subnet_ids            = ["subnet-0123456789abcdef0"]
      security_group_ids    = ["sg-0123456789abcdef0"]
    }
  }

  assert {
    condition = (
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).index_rotation_period == "OneWeek" &&
      one(aws_kinesis_firehose_delivery_stream.this.opensearch_configuration).retry_duration == 0
    )
    error_message = "Rotation and retry overrides must be passed through"
  }
}

run "s3_destination_has_no_backup_log_stream" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_stream.backup) == 0
    error_message = "The BackupDelivery log stream is only for the OpenSearch backup"
  }
}

# ---- negative: top-level inputs --------------------------------------------------------------------------------

run "name_too_long_is_rejected" {
  command = plan

  variables {
    name = "alpha-dev-raw-alpha-dev-raw-alpha-dev-raw-alpha-dev-raw-alpha-dev-raw-1"
  }

  expect_failures = [var.name]
}

run "name_with_a_space_is_rejected" {
  command = plan

  variables {
    name = "alpha dev"
  }

  expect_failures = [var.name]
}

run "role_arn_must_be_a_role" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:user/alpha-dev-firehose"
  }

  expect_failures = [var.role_arn]
}

run "role_arn_must_not_be_null" {
  command = plan

  variables {
    role_arn = null
  }

  expect_failures = [var.role_arn]
}

run "kms_key_alias_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "source_stream_must_be_a_kinesis_stream_arn" {
  command = plan

  variables {
    source_stream_arn = "arn:aws:s3:::alpha-dev-events"
  }

  expect_failures = [var.source_stream_arn]
}

run "log_retention_must_be_a_cloudwatch_value" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

# ---- negative: s3 ----------------------------------------------------------------------------------------------

run "bucket_arn_with_an_object_path_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw/raw"
      prefix     = "raw/"
    }
  }

  expect_failures = [var.s3]
}

run "bucket_name_instead_of_arn_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "alpha-dev-raw"
      prefix     = "raw/"
    }
  }

  expect_failures = [var.s3]
}

run "time_prefix_without_error_prefix_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn = "arn:aws:s3:::alpha-dev-raw"
      prefix     = "raw/!{timestamp:yyyy}/"
    }
  }

  expect_failures = [var.s3]
}

run "time_prefix_with_error_prefix_lacking_the_error_type_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
      prefix              = "raw/!{timestamp:yyyy}/"
      error_output_prefix = "errors/"
    }
  }

  expect_failures = [var.s3]
}

run "error_prefix_expression_without_the_error_type_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
      prefix              = "raw/"
      error_output_prefix = "errors/!{timestamp:yyyy}/"
    }
  }

  expect_failures = [var.s3]
}

run "prefix_must_not_contain_the_error_type" {
  command = plan

  variables {
    s3 = {
      bucket_arn          = "arn:aws:s3:::alpha-dev-raw"
      prefix              = "raw/!{firehose:error-output-type}/"
      error_output_prefix = "errors/!{firehose:error-output-type}/"
    }
  }

  expect_failures = [var.s3]
}

run "buffering_interval_above_900_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn         = "arn:aws:s3:::alpha-dev-raw"
      prefix             = "raw/"
      buffering_interval = 901
    }
  }

  expect_failures = [var.s3]
}

run "buffering_interval_below_zero_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn         = "arn:aws:s3:::alpha-dev-raw"
      prefix             = "raw/"
      buffering_interval = -1
    }
  }

  expect_failures = [var.s3]
}

run "buffering_size_above_128_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn     = "arn:aws:s3:::alpha-dev-raw"
      prefix         = "raw/"
      buffering_size = 129
    }
  }

  expect_failures = [var.s3]
}

run "buffering_size_below_1_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn     = "arn:aws:s3:::alpha-dev-raw"
      prefix         = "raw/"
      buffering_size = 0
    }
  }

  expect_failures = [var.s3]
}

run "unknown_compression_is_rejected" {
  command = plan

  variables {
    s3 = {
      bucket_arn  = "arn:aws:s3:::alpha-dev-raw"
      prefix      = "raw/"
      compression = "LZ4"
    }
  }

  expect_failures = [var.s3]
}

# ---- negative: opensearch --------------------------------------------------------------------------------------

run "opensearch_without_subnets_is_rejected" {
  command = plan

  variables {
    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "alpha-dev-events"
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_without_security_groups_is_rejected" {
  command = plan

  variables {
    opensearch = {
      domain_arn = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name = "alpha-dev-events"
      subnet_ids = ["subnet-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_domain_arn_must_be_a_domain" {
  command = plan

  variables {
    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/ALPHA"
      index_name         = "alpha-dev-events"
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_index_name_must_be_lowercase" {
  command = plan

  variables {
    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "Alpha-Events"
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_rotation_must_be_a_known_value" {
  command = plan

  variables {
    opensearch = {
      domain_arn            = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name            = "alpha-dev-events"
      index_rotation_period = "OneYear"
      subnet_ids            = ["subnet-0123456789abcdef0"]
      security_group_ids    = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_retry_above_7200_is_rejected" {
  command = plan

  variables {
    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "alpha-dev-events"
      retry_seconds      = 7201
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }

  expect_failures = [var.opensearch]
}

run "opensearch_with_too_many_security_groups_is_rejected" {
  command = plan

  variables {
    opensearch = {
      domain_arn         = "arn:aws:es:ap-northeast-1:111111111111:domain/alpha-dev-search"
      index_name         = "alpha-dev-events"
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0", "sg-1", "sg-2", "sg-3", "sg-4", "sg-5"]
    }
  }

  expect_failures = [var.opensearch]
}
