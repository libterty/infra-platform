mock_provider "aws" {}

variables {
  indexing             = null
  logging              = null
  event_configurations = null
}

# ---- positive -------------------------------------------------------------------------------------------------

run "nothing_is_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iot_indexing_configuration.this) == 0 && length(aws_iot_logging_options.this) == 0 && length(aws_iot_event_configurations.this) == 0
    error_message = "Every setting must be skipped when its input is null"
  }
}

run "all_three_settings" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode              = "REGISTRY_AND_SHADOW"
      thing_connectivity_indexing_mode = "STATUS"
      thing_group_indexing_mode        = "ON"
      custom_fields                    = { "attributes.model" = "String" }
    }
    logging = {
      role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
    }
    event_configurations = {
      THING                  = true
      THING_GROUP_MEMBERSHIP = true
      JOB                    = false
    }
  }

  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).thing_indexing_mode == "REGISTRY_AND_SHADOW"
    error_message = "thing_indexing_mode must be passed through"
  }
  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).thing_connectivity_indexing_mode == "STATUS"
    error_message = "thing_connectivity_indexing_mode must be passed through"
  }
  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).device_defender_indexing_mode == "OFF" && one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).named_shadow_indexing_mode == "OFF"
    error_message = "Unset indexing modes must default to OFF"
  }
  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_group_indexing_configuration).thing_group_indexing_mode == "ON"
    error_message = "thing_group_indexing_mode must be passed through"
  }
  assert {
    condition = one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).custom_field == toset([{
      name = "attributes.model"
      type = "String"
    }])
    error_message = "custom_fields must become custom_field blocks"
  }
  assert {
    condition     = aws_iot_logging_options.this[0].default_log_level == "WARN"
    error_message = "default_log_level must default to WARN"
  }
  assert {
    condition     = aws_iot_logging_options.this[0].role_arn == "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
    error_message = "logging.role_arn must be passed through"
  }
  assert {
    condition     = aws_iot_logging_options.this[0].disable_all_logs == false
    error_message = "Logging must never be disabled wholesale; use DISABLED as the level instead"
  }
  assert {
    condition     = aws_iot_event_configurations.this[0].event_configurations == tomap({ THING = true, THING_GROUP_MEMBERSHIP = true, JOB = false })
    error_message = "event_configurations must be passed through"
  }
}

run "only_logging" {
  command = plan

  variables {
    logging = {
      role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
      default_log_level = "ERROR"
    }
  }

  assert {
    condition     = length(aws_iot_logging_options.this) == 1 && aws_iot_logging_options.this[0].default_log_level == "ERROR"
    error_message = "Logging must be created with the given level"
  }
  assert {
    condition     = length(aws_iot_indexing_configuration.this) == 0 && length(aws_iot_event_configurations.this) == 0
    error_message = "Indexing and event configurations must be skipped when null"
  }
}

run "indexing_with_device_defender" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode           = "REGISTRY"
      device_defender_indexing_mode = "VIOLATIONS"
    }
  }

  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_indexing_configuration).device_defender_indexing_mode == "VIOLATIONS"
    error_message = "device_defender_indexing_mode must be passed through"
  }
  assert {
    condition     = one(aws_iot_indexing_configuration.this[0].thing_group_indexing_configuration).thing_group_indexing_mode == "OFF"
    error_message = "thing_group_indexing_mode must default to OFF"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "unknown_log_level_rejected" {
  command = plan

  variables {
    logging = {
      role_arn          = "arn:aws:iam::111111111111:role/alpha-dev-iot-logging"
      default_log_level = "TRACE"
    }
  }

  expect_failures = [var.logging]
}

run "logging_role_arn_format_rejected" {
  command = plan

  variables {
    logging = {
      role_arn = "alpha-dev-iot-logging"
    }
  }

  expect_failures = [var.logging]
}

run "unknown_thing_indexing_mode_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode = "SHADOW"
    }
  }

  expect_failures = [var.indexing]
}

run "unknown_connectivity_indexing_mode_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode              = "REGISTRY"
      thing_connectivity_indexing_mode = "ON"
    }
  }

  expect_failures = [var.indexing]
}

run "unknown_named_shadow_indexing_mode_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode        = "REGISTRY_AND_SHADOW"
      named_shadow_indexing_mode = "STATUS"
    }
  }

  expect_failures = [var.indexing]
}

run "unknown_thing_group_indexing_mode_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode       = "REGISTRY"
      thing_group_indexing_mode = "REGISTRY"
    }
  }

  expect_failures = [var.indexing]
}

run "unknown_custom_field_type_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode = "REGISTRY"
      custom_fields       = { "attributes.model" = "Text" }
    }
  }

  expect_failures = [var.indexing]
}

run "violations_with_thing_indexing_off_rejected" {
  command = plan

  variables {
    indexing = {
      thing_indexing_mode           = "OFF"
      device_defender_indexing_mode = "VIOLATIONS"
    }
  }

  expect_failures = [var.indexing]
}

run "unknown_event_type_rejected" {
  command = plan

  variables {
    event_configurations = { THINGS = true }
  }

  expect_failures = [var.event_configurations]
}
