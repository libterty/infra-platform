mock_provider "aws" {}

variables {
  project                  = "baseline"
  env                      = "dev"
  expected_account_id      = "111111111111"
  trail_log_retention_days = 90
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/trail_bucket_name"]
  values = { insecure_value = "baseline-dev-trail-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/config_bucket_name"]
  values = { insecure_value = "baseline-dev-config-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/config_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/baseline-dev-config-recorder" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/trail_logs_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/baseline-dev-trail-logs" }
}

override_module {
  target = module.trail_log_group
  outputs = {
    name = "/aws/cloudtrail/baseline-dev"
    arn  = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev"
  }
}

run "reads_only_the_keys_it_needs" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn         = "foundation/kms_key_arn"
      trail_bucket_name   = "foundation/trail_bucket_name"
      config_bucket_name  = "foundation/config_bucket_name"
      alert_topic_arn     = "foundation/alert_topic_arn"
      config_role_arn     = "iam/config_role_arn"
      trail_logs_role_arn = "iam/trail_logs_role_arn"
    } && local.ssm_input_lists == {}
    error_message = "audit reads the governance key, both log buckets, the alert topic and the Config and trail log roles only (design 8.2)"
  }
}

run "trail_is_multi_region_with_the_governance_key" {
  command = plan

  assert {
    condition     = local.trail.is_multi_region_trail == true
    error_message = "The trail must record every region (design K5)"
  }

  assert {
    condition     = local.trail.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "The trail must be encrypted with the governance key of foundation (design K5)"
  }

  assert {
    condition     = local.trail.s3_bucket_name == "baseline-dev-trail-111111111111" && local.trail.name == "baseline-dev-trail"
    error_message = "The trail must be <name_prefix>-trail and write to the trail bucket of foundation"
  }

  assert {
    condition     = length(regexall("advanced_event_selectors|insight_types|is_organization_trail", file("${path.module}/trail.tf"))) == 0
    error_message = "The trail records management events only; data events and Insights are billed and stay off (design K5)"
  }
}

run "trail_sends_to_its_log_group_with_the_iam_role" {
  command = plan

  assert {
    condition     = local.trail_log_group_name == "/aws/cloudtrail/baseline-dev"
    error_message = "The log group must follow the naming rule of iam/naming.tf; the trail log role may write only there"
  }

  assert {
    condition = local.trail.cloudwatch_logs == {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev:*"
      role_arn      = "arn:aws:iam::111111111111:role/baseline-dev-trail-logs"
    }
    error_message = "CloudTrail needs the log group ARN with ':*' and the trail log role of the iam stack"
  }
}

run "log_group_is_encrypted_and_kept_per_env" {
  command = plan

  assert {
    condition = local.trail_log_group == {
      name           = "/aws/cloudtrail/baseline-dev"
      retention_days = 90
      kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    }
    error_message = "The trail log group must follow the naming rule, keep the env retention and use the governance key"
  }
}

run "two_alarms_go_to_the_alert_topic" {
  command = plan

  assert {
    condition     = toset(keys(local.trail_alarms)) == toset(["root_account_usage", "unauthorized_api_calls"])
    error_message = "There must be exactly the root usage and unauthorized API call alarms (design K6)"
  }

  assert {
    condition     = local.trail_alarm_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts"]
    error_message = "The alarms must notify the alert topic of foundation and nothing else"
  }

  assert {
    condition     = length(regexall("(?m)^\\s*sns_topic_arns\\s*=\\s*local\\.trail_alarm_topic_arns\\s*$", file("${path.module}/alarms.tf"))) == 1
    error_message = "log-metric-alarm must take its topics from trail_alarm_topic_arns"
  }

  assert {
    condition = (
      strcontains(local.trail_alarms.root_account_usage.pattern, "$.userIdentity.type = \"Root\"") &&
      strcontains(local.trail_alarms.unauthorized_api_calls.pattern, "*UnauthorizedOperation") &&
      strcontains(local.trail_alarms.unauthorized_api_calls.pattern, "AccessDenied*")
    )
    error_message = "The patterns must match root activity and UnauthorizedOperation or AccessDenied errors"
  }

  assert {
    condition = module.trail_alarms.alarm_names == {
      root_account_usage     = "baseline-dev-trail-root-account-usage"
      unauthorized_api_calls = "baseline-dev-trail-unauthorized-api-calls"
    }
    error_message = "log-metric-alarm must create both alarms on the trail log group"
  }
}

run "config_records_everything_continuously" {
  command = plan

  assert {
    condition = local.config_recorder == {
      name                = "default"
      role_arn            = "arn:aws:iam::111111111111:role/baseline-dev-config-recorder"
      s3_bucket_name      = "baseline-dev-config-111111111111"
      s3_kms_key_arn      = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
      recording           = { include_global_resource_types = true, exclusion_types = [] }
      recording_frequency = "CONTINUOUS"
      retention_days      = 2557
    }
    error_message = "Config must record all types with global types in this primary region, continuously, with the iam role, the config bucket and the governance key (design 8.3)"
  }
}

run "publishes_the_trail_and_the_recorder" {
  command = plan

  override_module {
    target = module.trail
    outputs = {
      arn = "arn:aws:cloudtrail:ap-northeast-1:111111111111:trail/baseline-dev-trail"
    }
  }

  override_module {
    target = module.config_recorder
    outputs = {
      recorder_name = "default"
    }
  }

  assert {
    condition = local.published_strings == {
      trail_arn            = "arn:aws:cloudtrail:ap-northeast-1:111111111111:trail/baseline-dev-trail"
      config_recorder_name = "default"
    }
    error_message = "audit publishes the trail ARN and the recorder name only (design 8.2)"
  }

  assert {
    condition = module.ssm_publish.names == {
      trail_arn            = "/baseline/dev/audit/trail_arn"
      config_recorder_name = "/baseline/dev/audit/config_recorder_name"
    }
    error_message = "ssm-publish must write the keys under the audit stack path"
  }
}

# The stack cannot see inside the cloudtrail module, so this run plans the same registry module with the values the
# stack passes and pins what the module fixes: log file validation, multi-region, the CMK and the log group.
run "cloudtrail_module_validates_log_files" {
  command = plan

  module {
    source  = "app.terraform.io/libterty/cloudtrail/aws"
    version = "~> 0.1.0"
  }

  variables {
    name                  = "baseline-dev-trail"
    s3_bucket_name        = "baseline-dev-trail-111111111111"
    kms_key_arn           = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    is_multi_region_trail = true
    cloudwatch_logs = {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev:*"
      role_arn      = "arn:aws:iam::111111111111:role/baseline-dev-trail-logs"
    }
  }

  assert {
    condition = (
      aws_cloudtrail.this.enable_log_file_validation == true &&
      aws_cloudtrail.this.is_multi_region_trail == true &&
      aws_cloudtrail.this.kms_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" &&
      aws_cloudtrail.this.cloud_watch_logs_group_arn == "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev:*"
    )
    error_message = "The trail must validate log files, cover every region, use the CMK and send to the log group (design K5)"
  }
}

run "log_group_arn_without_wildcard_rejected" {
  command = plan

  module {
    source  = "app.terraform.io/libterty/cloudtrail/aws"
    version = "~> 0.1.0"
  }

  variables {
    name           = "baseline-dev-trail"
    s3_bucket_name = "baseline-dev-trail-111111111111"
    kms_key_arn    = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    cloudwatch_logs = {
      log_group_arn = "arn:aws:logs:ap-northeast-1:111111111111:log-group:/aws/cloudtrail/baseline-dev"
      role_arn      = "arn:aws:iam::111111111111:role/baseline-dev-trail-logs"
    }
  }

  expect_failures = [var.cloudwatch_logs]
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
    condition     = local.name_prefix == "baseline-dev" && local.ssm_prefix == "/baseline/dev"
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
    condition     = local.name_prefix == "baseline-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
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
