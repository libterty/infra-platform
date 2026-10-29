mock_provider "aws" {}

variables {
  name           = "default"
  role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-config-recorder"
  s3_bucket_name = "alpha-dev-audit-logs"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "all_resources_with_global_types" {
  command = plan

  assert {
    condition     = aws_config_configuration_recorder.this.name == "default" && aws_config_configuration_recorder.this.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-config-recorder"
    error_message = "Name and role must be passed through"
  }

  assert {
    condition = (
      aws_config_configuration_recorder.this.recording_group[0].all_supported == true &&
      aws_config_configuration_recorder.this.recording_group[0].include_global_resource_types == true &&
      aws_config_configuration_recorder.this.recording_group[0].recording_strategy[0].use_only == "ALL_SUPPORTED_RESOURCE_TYPES" &&
      length(aws_config_configuration_recorder.this.recording_group[0].exclusion_by_resource_types) == 0
    )
    error_message = "By default every supported resource type and the global IAM types must be recorded"
  }

  assert {
    condition     = aws_config_configuration_recorder.this.recording_mode[0].recording_frequency == "CONTINUOUS"
    error_message = "Recording must be continuous by default"
  }

  assert {
    condition     = aws_config_delivery_channel.this.name == "default" && aws_config_delivery_channel.this.s3_bucket_name == "alpha-dev-audit-logs"
    error_message = "The delivery channel must write to the given bucket"
  }

  assert {
    condition     = aws_config_delivery_channel.this.snapshot_delivery_properties[0].delivery_frequency == "TwentyFour_Hours"
    error_message = "Snapshots must be delivered every 24 hours by default"
  }

  assert {
    condition     = aws_config_configuration_recorder_status.this.name == "default" && aws_config_configuration_recorder_status.this.is_enabled == true
    error_message = "The recorder must be started"
  }

  assert {
    condition     = aws_config_retention_configuration.this.retention_period_in_days == 2557
    error_message = "Configuration items must be kept 2557 days by default"
  }

  assert {
    condition     = length(aws_config_config_rule.this) == 0 && length(aws_config_configuration_aggregator.this) == 0
    error_message = "No rule or aggregator without managed_rules or aggregator"
  }
}

run "daily_recording_with_delivery_options" {
  command = plan

  variables {
    recording_frequency = "DAILY"
    snapshot_frequency  = "Six_Hours"
    retention_days      = 30
    s3_key_prefix       = "config"
    s3_kms_key_arn      = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    sns_topic_arn       = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-security"
    region              = "us-east-1"
  }

  assert {
    condition     = aws_config_configuration_recorder.this.recording_mode[0].recording_frequency == "DAILY"
    error_message = "recording_frequency must be passed through"
  }

  assert {
    condition = (
      aws_config_delivery_channel.this.s3_key_prefix == "config" &&
      aws_config_delivery_channel.this.s3_kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" &&
      aws_config_delivery_channel.this.sns_topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-security" &&
      aws_config_delivery_channel.this.snapshot_delivery_properties[0].delivery_frequency == "Six_Hours"
    )
    error_message = "Delivery options must be passed through"
  }

  assert {
    condition     = aws_config_retention_configuration.this.retention_period_in_days == 30
    error_message = "retention_days must be passed through"
  }

  assert {
    condition = alltrue([
      aws_config_configuration_recorder.this.region == "us-east-1",
      aws_config_delivery_channel.this.region == "us-east-1",
      aws_config_configuration_recorder_status.this.region == "us-east-1",
      aws_config_retention_configuration.this.region == "us-east-1",
    ])
    error_message = "region must be set on every resource"
  }
}

run "exclusions_without_global_types" {
  command = plan

  variables {
    recording = {
      include_global_resource_types = false
      exclusion_types               = ["AWS::EC2::NetworkInterface", "AWS::RDS::GlobalCluster"]
    }
  }

  assert {
    condition = (
      aws_config_configuration_recorder.this.recording_group[0].all_supported == false &&
      aws_config_configuration_recorder.this.recording_group[0].include_global_resource_types == false &&
      aws_config_configuration_recorder.this.recording_group[0].recording_strategy[0].use_only == "EXCLUSION_BY_RESOURCE_TYPES" &&
      toset(aws_config_configuration_recorder.this.recording_group[0].exclusion_by_resource_types[0].resource_types) == toset(["AWS::EC2::NetworkInterface", "AWS::RDS::GlobalCluster"])
    )
    error_message = "Exclusions must switch to the exclusion recording strategy"
  }
}

run "global_types_only_in_one_region" {
  command = plan

  variables {
    region    = "us-west-2"
    recording = { include_global_resource_types = false }
  }

  assert {
    condition     = aws_config_configuration_recorder.this.recording_group[0].all_supported == true && aws_config_configuration_recorder.this.recording_group[0].include_global_resource_types == false
    error_message = "A secondary region records all regional types without the global IAM types"
  }
}

run "managed_rules" {
  command = plan

  variables {
    managed_rules = {
      S3_BUCKET_VERSIONING_ENABLED = {
        scope_resource_types = ["AWS::S3::Bucket"]
      }
      ACCESS_KEYS_ROTATED = {
        input_parameters = { maxAccessKeyAge = "90" }
      }
    }
  }

  assert {
    condition     = aws_config_config_rule.this["S3_BUCKET_VERSIONING_ENABLED"].name == "s3-bucket-versioning-enabled"
    error_message = "The rule name is the identifier in lower kebab case"
  }

  assert {
    condition     = aws_config_config_rule.this["S3_BUCKET_VERSIONING_ENABLED"].source[0].owner == "AWS" && aws_config_config_rule.this["S3_BUCKET_VERSIONING_ENABLED"].source[0].source_identifier == "S3_BUCKET_VERSIONING_ENABLED"
    error_message = "Rules must be AWS managed rules with the given identifier"
  }

  assert {
    condition     = aws_config_config_rule.this["S3_BUCKET_VERSIONING_ENABLED"].scope[0].compliance_resource_types == toset(["AWS::S3::Bucket"]) && aws_config_config_rule.this["S3_BUCKET_VERSIONING_ENABLED"].input_parameters == null
    error_message = "Scope must be passed through and no input parameters sent when none are given"
  }

  assert {
    condition     = jsondecode(aws_config_config_rule.this["ACCESS_KEYS_ROTATED"].input_parameters) == { maxAccessKeyAge = "90" } && length(aws_config_config_rule.this["ACCESS_KEYS_ROTATED"].scope) == 0
    error_message = "Input parameters must be JSON encoded and no scope sent when none is given"
  }
}

run "account_aggregator" {
  command = plan

  variables {
    aggregator = {
      name        = "alpha-accounts"
      account_ids = ["111111111111", "222222222222"]
    }
  }

  assert {
    condition = (
      aws_config_configuration_aggregator.this[0].name == "alpha-accounts" &&
      aws_config_configuration_aggregator.this[0].account_aggregation_source[0].account_ids == tolist(["111111111111", "222222222222"]) &&
      aws_config_configuration_aggregator.this[0].account_aggregation_source[0].all_regions == true &&
      length(aws_config_configuration_aggregator.this[0].organization_aggregation_source) == 0
    )
    error_message = "An account aggregator over all regions must be created"
  }
}

run "organization_aggregator" {
  command = plan

  variables {
    aggregator = {
      name                  = "organization"
      organization_role_arn = "arn:aws:iam::333333333333:role/config-aggregator"
      regions               = ["ap-northeast-1", "us-east-1"]
    }
  }

  assert {
    condition = (
      aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].role_arn == "arn:aws:iam::333333333333:role/config-aggregator" &&
      aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].all_regions == false &&
      aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].regions == tolist(["ap-northeast-1", "us-east-1"]) &&
      length(aws_config_configuration_aggregator.this[0].account_aggregation_source) == 0
    )
    error_message = "An organization aggregator over the given regions must be created"
  }
}

run "outputs" {
  command = apply

  variables {
    aggregator = {
      name        = "alpha-accounts"
      account_ids = ["111111111111"]
    }
  }

  override_resource {
    target = aws_config_configuration_aggregator.this
    values = {
      arn = "arn:aws:config:ap-northeast-1:111111111111:config-aggregator/config-aggregator-abcdefgh"
    }
  }

  assert {
    condition     = output.recorder_name == "default" && output.delivery_channel_name == "default"
    error_message = "Outputs must expose the recorder and delivery channel names"
  }

  assert {
    condition     = output.aggregator_arn == "arn:aws:config:ap-northeast-1:111111111111:config-aggregator/config-aggregator-abcdefgh"
    error_message = "aggregator_arn must expose the aggregator ARN"
  }
}

run "no_aggregator_arn_without_aggregator" {
  command = apply

  assert {
    condition     = output.aggregator_arn == null
    error_message = "aggregator_arn must be null without an aggregator"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "both_aggregator_kinds_rejected" {
  command = plan

  variables {
    aggregator = {
      name                  = "mixed"
      account_ids           = ["111111111111"]
      organization_role_arn = "arn:aws:iam::333333333333:role/config-aggregator"
    }
  }

  expect_failures = [var.aggregator]
}

run "aggregator_without_source_rejected" {
  command = plan

  variables {
    aggregator = {
      name = "empty"
    }
  }

  expect_failures = [var.aggregator]
}

run "aggregator_account_id_must_be_12_digits" {
  command = plan

  variables {
    aggregator = {
      name        = "short"
      account_ids = ["11111111111"]
    }
  }

  expect_failures = [var.aggregator]
}

run "aggregator_role_must_be_a_role_arn" {
  command = plan

  variables {
    aggregator = {
      name                  = "organization"
      organization_role_arn = "arn:aws:iam::333333333333:user/config"
    }
  }

  expect_failures = [var.aggregator]
}

run "retention_29_days_rejected" {
  command = plan

  variables {
    retention_days = 29
  }

  expect_failures = [var.retention_days]
}

run "retention_over_2557_days_rejected" {
  command = plan

  variables {
    retention_days = 2558
  }

  expect_failures = [var.retention_days]
}

run "invalid_role_arn_rejected" {
  command = plan

  variables {
    role_arn = "arn:aws:iam::111111111111:policy/alpha-dev-config"
  }

  expect_failures = [var.role_arn]
}

run "lower_case_rule_identifier_rejected" {
  command = plan

  variables {
    managed_rules = {
      s3-bucket-versioning-enabled = {}
    }
  }

  expect_failures = [var.managed_rules]
}

run "unknown_recording_frequency_rejected" {
  command = plan

  variables {
    recording_frequency = "HOURLY"
  }

  expect_failures = [var.recording_frequency]
}

run "unknown_snapshot_frequency_rejected" {
  command = plan

  variables {
    snapshot_frequency = "Two_Hours"
  }

  expect_failures = [var.snapshot_frequency]
}

run "exclusions_with_global_types_rejected" {
  command = plan

  variables {
    recording = {
      exclusion_types = ["AWS::EC2::NetworkInterface"]
    }
  }

  expect_failures = [var.recording]
}

run "invalid_exclusion_type_rejected" {
  command = plan

  variables {
    recording = {
      include_global_resource_types = false
      exclusion_types               = ["ec2:network-interface"]
    }
  }

  expect_failures = [var.recording]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    s3_kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/audit"
  }

  expect_failures = [var.s3_kms_key_arn]
}

run "invalid_sns_topic_rejected" {
  command = plan

  variables {
    sns_topic_arn = "alpha-dev-security"
  }

  expect_failures = [var.sns_topic_arn]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    region = "us_east_1"
  }

  expect_failures = [var.region]
}
