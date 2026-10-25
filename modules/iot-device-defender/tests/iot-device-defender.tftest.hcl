mock_provider "awscc" {}

variables {
  account_id = "111111111111"

  audit = {
    role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
    checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    sns = {
      target_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit"
      role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit-sns"
    }
  }

  scheduled_audits = {
    alpha-dev-daily = {
      frequency = "DAILY"
      checks    = ["LOGGING_DISABLED_CHECK"]
    }
    alpha-dev-weekly = {
      frequency   = "WEEKLY"
      day_of_week = "MON"
      checks      = ["DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    }
  }

  mitigation_actions = {
    alpha-dev-quarantine = {
      role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
      add_things_to_thing_group = { thing_group_names = ["alpha-dev-quarantine"] }
    }
    alpha-dev-notify = {
      role_arn               = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
      publish_finding_to_sns = { topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit" }
    }
  }

  tags = { Project = "alpha" }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "audit_configuration_enables_only_the_listed_checks" {
  command = plan

  assert {
    condition     = length(awscc_iot_account_audit_configuration.this) == 1
    error_message = "The account audit configuration must be created when audit is given"
  }

  assert {
    condition     = awscc_iot_account_audit_configuration.this[0].account_id == "111111111111" && awscc_iot_account_audit_configuration.this[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
    error_message = "account_id and role_arn must be passed through"
  }

  assert {
    condition = (
      awscc_iot_account_audit_configuration.this[0].audit_check_configurations.logging_disabled_check.enabled == true &&
      awscc_iot_account_audit_configuration.this[0].audit_check_configurations.device_certificate_expiring_check.enabled == true &&
      awscc_iot_account_audit_configuration.this[0].audit_check_configurations.iot_policy_overly_permissive_check.enabled == true
    )
    error_message = "Listed checks must be enabled"
  }

  assert {
    condition = (
      awscc_iot_account_audit_configuration.this[0].audit_check_configurations.conflicting_client_ids_check.enabled == false &&
      awscc_iot_account_audit_configuration.this[0].audit_check_configurations.io_t_policy_potential_mis_configuration_check.enabled == false
    )
    error_message = "Checks that are not listed must be explicitly disabled"
  }

  assert {
    condition = (
      awscc_iot_account_audit_configuration.this[0].audit_notification_target_configurations.sns.enabled == true &&
      awscc_iot_account_audit_configuration.this[0].audit_notification_target_configurations.sns.target_arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit"
    )
    error_message = "SNS notifications must be enabled with the given topic"
  }
}

run "potential_misconfiguration_check_maps_to_its_attribute" {
  command = plan

  variables {
    audit = {
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
      checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK", "IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK"]
    }
  }

  assert {
    condition     = awscc_iot_account_audit_configuration.this[0].audit_check_configurations.io_t_policy_potential_mis_configuration_check.enabled == true
    error_message = "IOT_POLICY_POTENTIAL_MIS_CONFIGURATION_CHECK must map to io_t_policy_potential_mis_configuration_check"
  }
}

run "scheduled_audits" {
  command = plan

  assert {
    condition     = length(awscc_iot_scheduled_audit.this) == 2
    error_message = "One scheduled audit must be created per map entry"
  }

  assert {
    condition = (
      awscc_iot_scheduled_audit.this["alpha-dev-weekly"].scheduled_audit_name == "alpha-dev-weekly" &&
      awscc_iot_scheduled_audit.this["alpha-dev-weekly"].frequency == "WEEKLY" &&
      awscc_iot_scheduled_audit.this["alpha-dev-weekly"].day_of_week == "MON" &&
      awscc_iot_scheduled_audit.this["alpha-dev-weekly"].target_check_names == toset(["DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"])
    )
    error_message = "Scheduled audit fields must be passed through"
  }
}

run "monthly_audit_on_the_last_day" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-monthly = { frequency = "MONTHLY", day_of_month = "LAST", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  assert {
    condition     = awscc_iot_scheduled_audit.this["alpha-dev-monthly"].day_of_month == "LAST"
    error_message = "day_of_month must be passed through"
  }
}

run "mitigation_actions_carry_exactly_one_action" {
  command = plan

  assert {
    condition = (
      awscc_iot_mitigation_action.this["alpha-dev-quarantine"].action_name == "alpha-dev-quarantine" &&
      awscc_iot_mitigation_action.this["alpha-dev-quarantine"].action_params.add_things_to_thing_group_params.thing_group_names == toset(["alpha-dev-quarantine"]) &&
      awscc_iot_mitigation_action.this["alpha-dev-quarantine"].action_params.add_things_to_thing_group_params.override_dynamic_groups == false
    )
    error_message = "add_things_to_thing_group must map to add_things_to_thing_group_params"
  }

  assert {
    condition = (
      awscc_iot_mitigation_action.this["alpha-dev-notify"].action_params.publish_finding_to_sns_params.topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit"
    )
    error_message = "publish_finding_to_sns must map to publish_finding_to_sns_params"
  }
}

run "other_mitigation_action_types" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-deactivate = {
        role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        update_device_certificate = {}
      }
      alpha-dev-logging = {
        role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        enable_iot_logging = { role_arn_for_logging = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging", log_level = "ERROR" }
      }
    }
  }

  assert {
    condition     = awscc_iot_mitigation_action.this["alpha-dev-deactivate"].action_params.update_device_certificate_params.action == "DEACTIVATE"
    error_message = "update_device_certificate must deactivate the certificate"
  }

  assert {
    condition = (
      awscc_iot_mitigation_action.this["alpha-dev-logging"].action_params.enable_io_t_logging_params.log_level == "ERROR" &&
      awscc_iot_mitigation_action.this["alpha-dev-logging"].action_params.enable_io_t_logging_params.role_arn_for_logging == "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
    )
    error_message = "enable_iot_logging must map to enable_io_t_logging_params"
  }
}

run "tags_are_converted_to_key_value_sets" {
  command = plan

  assert {
    condition = awscc_iot_scheduled_audit.this["alpha-dev-daily"].tags == toset([
      { key = "Name", value = "alpha-dev-daily" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Scheduled audit tags must be a set of key/value objects including Name"
  }

  assert {
    condition = awscc_iot_mitigation_action.this["alpha-dev-notify"].tags == toset([
      { key = "Name", value = "alpha-dev-notify" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Mitigation action tags must be a set of key/value objects including Name"
  }
}

run "audit_null_creates_only_the_schedules" {
  command = plan

  variables {
    audit      = null
    account_id = null
  }

  assert {
    condition     = length(awscc_iot_account_audit_configuration.this) == 0
    error_message = "audit = null must not create the account audit configuration"
  }

  assert {
    condition     = length(awscc_iot_scheduled_audit.this) == 2
    error_message = "Scheduled audits must still be created when audit is null"
  }
}

run "outputs_after_apply" {
  override_resource {
    target = awscc_iot_scheduled_audit.this["alpha-dev-daily"]
    values = {
      scheduled_audit_arn = "arn:aws:iot:ap-northeast-1:111111111111:scheduledaudit/alpha-dev-daily"
    }
  }

  override_resource {
    target = awscc_iot_mitigation_action.this["alpha-dev-notify"]
    values = {
      mitigation_action_arn = "arn:aws:iot:ap-northeast-1:111111111111:mitigationaction/alpha-dev-notify"
    }
  }

  assert {
    condition     = output.scheduled_audit_arns["alpha-dev-daily"] == "arn:aws:iot:ap-northeast-1:111111111111:scheduledaudit/alpha-dev-daily"
    error_message = "scheduled_audit_arns must map names to ARNs"
  }

  assert {
    condition     = output.mitigation_action_arns["alpha-dev-notify"] == "arn:aws:iot:ap-northeast-1:111111111111:mitigationaction/alpha-dev-notify"
    error_message = "mitigation_action_arns must map names to ARNs"
  }

  assert {
    condition     = length(output.scheduled_audit_arns) == 2 && length(output.mitigation_action_arns) == 2
    error_message = "Every scheduled audit and mitigation action must be in the outputs"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "scheduled_check_not_enabled_in_audit_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-daily = { frequency = "DAILY", checks = ["CONFLICTING_CLIENT_IDS_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "unknown_scheduled_check_rejected" {
  command = plan

  variables {
    audit = null
    scheduled_audits = {
      alpha-dev-daily = { frequency = "DAILY", checks = ["BOGUS_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "scheduled_audit_without_checks_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-daily = { frequency = "DAILY", checks = [] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "unknown_frequency_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-hourly = { frequency = "HOURLY", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "weekly_without_day_of_week_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-weekly = { frequency = "WEEKLY", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "daily_with_day_of_week_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-daily = { frequency = "DAILY", day_of_week = "MON", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "monthly_with_day_of_week_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-monthly = { frequency = "MONTHLY", day_of_week = "MON", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "monthly_day_out_of_range_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-monthly = { frequency = "MONTHLY", day_of_month = "32", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "biweekly_with_invalid_day_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      alpha-dev-biweekly = { frequency = "BIWEEKLY", day_of_week = "MONDAY", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "invalid_scheduled_audit_name_rejected" {
  command = plan

  variables {
    scheduled_audits = {
      "alpha dev daily" = { frequency = "DAILY", checks = ["LOGGING_DISABLED_CHECK"] }
    }
  }

  expect_failures = [var.scheduled_audits]
}

run "mitigation_with_two_actions_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-both = {
        role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        add_things_to_thing_group = { thing_group_names = ["alpha-dev-quarantine"] }
        update_device_certificate = {}
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_without_action_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-none = { role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation" }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_role_arn_format_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-notify = {
        role_arn               = "alpha-dev-iot-mitigation"
        publish_finding_to_sns = { topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit" }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_topic_arn_format_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-notify = {
        role_arn               = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        publish_finding_to_sns = { topic_arn = "arn:aws:sqs:ap-northeast-1:111111111111:alpha-dev-iot-audit" }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_empty_thing_group_list_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-quarantine = {
        role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        add_things_to_thing_group = { thing_group_names = [] }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_update_certificate_action_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-deactivate = {
        role_arn                  = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        update_device_certificate = { action = "REVOKE" }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "mitigation_log_level_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      alpha-dev-logging = {
        role_arn           = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        enable_iot_logging = { role_arn_for_logging = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging", log_level = "DISABLED" }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "invalid_mitigation_name_rejected" {
  command = plan

  variables {
    mitigation_actions = {
      "alpha/dev" = {
        role_arn               = "arn:aws:iam::111111111111:role/alpha-dev-iot-mitigation"
        publish_finding_to_sns = { topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-iot-audit" }
      }
    }
  }

  expect_failures = [var.mitigation_actions]
}

run "unknown_audit_check_rejected" {
  command = plan

  variables {
    audit = {
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
      checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK", "logging_disabled_check"]
    }
  }

  expect_failures = [var.audit]
}

run "audit_without_checks_rejected" {
  command = plan

  variables {
    audit            = { role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit", checks = [] }
    scheduled_audits = {}
  }

  expect_failures = [var.audit]
}

run "audit_role_arn_format_rejected" {
  command = plan

  variables {
    audit = {
      role_arn = "arn:aws:iam::111111111111:user/alpha-dev"
      checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
    }
  }

  expect_failures = [var.audit]
}

run "audit_sns_target_format_rejected" {
  command = plan

  variables {
    audit = {
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit"
      checks   = ["LOGGING_DISABLED_CHECK", "DEVICE_CERTIFICATE_EXPIRING_CHECK", "IOT_POLICY_OVERLY_PERMISSIVE_CHECK"]
      sns = {
        target_arn = "alpha-dev-iot-audit"
        role_arn   = "arn:aws:iam::111111111111:role/alpha-dev-iot-audit-sns"
      }
    }
  }

  expect_failures = [var.audit]
}

run "account_id_required_with_audit_rejected" {
  command = plan

  variables {
    account_id = null
  }

  expect_failures = [var.account_id]
}

run "account_id_format_rejected" {
  command = plan

  variables {
    account_id = "1111"
  }

  expect_failures = [var.account_id]
}
