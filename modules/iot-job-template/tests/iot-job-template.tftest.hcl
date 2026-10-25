mock_provider "awscc" {}

variables {
  job_template_id = "alpha-dev-firmware-update"
  description     = "Firmware update for non-Greengrass devices."

  document = {
    operation = "firmware-update"
    files     = [{ url = "$${aws:iot:s3-presigned-url:https://s3.amazonaws.com/alpha-dev-ota-artifacts/firmware/1.2.0.bin}" }]
  }
}

# ---- positive -------------------------------------------------------------------------------------------------

run "inline_document_is_json_encoded" {
  command = plan

  assert {
    condition     = jsondecode(awscc_iot_job_template.this.document).operation == "firmware-update"
    error_message = "The document object must be JSON-encoded by the module"
  }

  assert {
    condition     = awscc_iot_job_template.this.job_template_id == "alpha-dev-firmware-update" && awscc_iot_job_template.this.description == "Firmware update for non-Greengrass devices."
    error_message = "Id and description must be passed through"
  }
}

run "s3_document_source" {
  command = plan

  variables {
    document        = null
    document_source = "s3://alpha-dev-ota-artifacts/jobs/firmware-update.json"
  }

  assert {
    condition     = awscc_iot_job_template.this.document_source == "s3://alpha-dev-ota-artifacts/jobs/firmware-update.json"
    error_message = "document_source must be passed through"
  }
}

run "presigned_url_rollout_abort_retry_timeout_windows" {
  command = plan

  variables {
    presigned_url = {
      role_arn       = "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign"
      expires_in_sec = 900
    }
    rollout = {
      exponential = { base_rate_per_minute = 5, increment_factor = 2, number_of_succeeded_things = 10 }
    }
    abort = [
      { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
    ]
    retry = [
      { failure_type = "FAILED", number_of_retries = 2 },
      { failure_type = "TIMED_OUT", number_of_retries = 0 },
    ]
    timeout_minutes = 60
    maintenance_windows = [
      { start_time = "cron(0 18 ? * MON-FRI *)", duration_minutes = 120 },
    ]
  }

  assert {
    condition     = awscc_iot_job_template.this.presigned_url_config.role_arn == "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign" && awscc_iot_job_template.this.presigned_url_config.expires_in_sec == 900
    error_message = "presigned URL config must be passed through"
  }

  assert {
    condition     = awscc_iot_job_template.this.job_executions_rollout_config.exponential_rollout_rate.increment_factor == 2 && awscc_iot_job_template.this.job_executions_rollout_config.exponential_rollout_rate.rate_increase_criteria.number_of_succeeded_things == 10
    error_message = "exponential rollout must be passed through"
  }

  assert {
    condition = awscc_iot_job_template.this.abort_config.criteria_list == tolist([{
      action                        = "CANCEL"
      failure_type                  = "FAILED"
      threshold_percentage          = 10
      min_number_of_executed_things = 5
    }])
    error_message = "abort criteria must be passed through with action CANCEL"
  }

  assert {
    condition = awscc_iot_job_template.this.job_executions_retry_config.retry_criteria_list == tolist([
      { failure_type = "FAILED", number_of_retries = 2 },
      { failure_type = "TIMED_OUT", number_of_retries = 0 },
    ])
    error_message = "retry criteria must be passed through"
  }

  assert {
    condition     = awscc_iot_job_template.this.timeout_config.in_progress_timeout_in_minutes == 60
    error_message = "timeout must be passed through"
  }

  assert {
    condition     = awscc_iot_job_template.this.maintenance_windows == tolist([{ start_time = "cron(0 18 ? * MON-FRI *)", duration_in_minutes = 120 }])
    error_message = "maintenance windows must be passed through"
  }
}

run "presigned_url_expiry_defaults_to_3600" {
  command = plan

  variables {
    presigned_url = { role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign" }
  }

  assert {
    condition     = awscc_iot_job_template.this.presigned_url_config.expires_in_sec == 3600
    error_message = "expires_in_sec must default to 3600"
  }
}

run "rollout_maximum_per_minute" {
  command = plan

  variables {
    rollout = { maximum_per_minute = 100 }
  }

  assert {
    condition     = awscc_iot_job_template.this.job_executions_rollout_config.maximum_per_minute == 100
    error_message = "maximum_per_minute must be passed through"
  }
}

run "tags_are_a_set_of_key_value_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha", Environment = "dev" }
  }

  assert {
    condition = awscc_iot_job_template.this.tags == toset([
      { key = "Environment", value = "dev" },
      { key = "Name", value = "alpha-dev-firmware-update" },
      { key = "Project", value = "alpha" },
    ])
    error_message = "Tags must be converted to a set of key/value objects plus Name"
  }
}

run "outputs_after_apply" {
  override_resource {
    target = awscc_iot_job_template.this
    values = {
      arn = "arn:aws:iot:ap-northeast-1:111111111111:jobtemplate/alpha-dev-firmware-update"
    }
  }

  assert {
    condition     = output.arn == "arn:aws:iot:ap-northeast-1:111111111111:jobtemplate/alpha-dev-firmware-update"
    error_message = "arn output must be the job template ARN"
  }

  assert {
    condition     = output.job_template_id == "alpha-dev-firmware-update"
    error_message = "job_template_id output must be the template id"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "both_documents_rejected" {
  command = plan

  variables {
    document_source = "s3://alpha-dev-ota-artifacts/jobs/firmware-update.json"
  }

  expect_failures = [var.document_source]
}

run "no_document_rejected" {
  command = plan

  variables {
    document = null
  }

  expect_failures = [var.document_source]
}

run "document_not_an_object_rejected" {
  command = plan

  variables {
    document = "{\"operation\":\"reboot\"}"
  }

  expect_failures = [var.document]
}

run "document_source_not_s3_rejected" {
  command = plan

  variables {
    document        = null
    document_source = "https://alpha-dev-ota-artifacts.s3.amazonaws.com/jobs/firmware-update.json"
  }

  expect_failures = [var.document_source]
}

run "invalid_job_template_id_rejected" {
  command = plan

  variables {
    job_template_id = "alpha dev/firmware"
  }

  expect_failures = [var.job_template_id]
}

run "empty_description_rejected" {
  command = plan

  variables {
    description = ""
  }

  expect_failures = [var.description]
}

run "expires_in_sec_below_60_rejected" {
  command = plan

  variables {
    presigned_url = { role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign", expires_in_sec = 59 }
  }

  expect_failures = [var.presigned_url]
}

run "expires_in_sec_above_3600_rejected" {
  command = plan

  variables {
    presigned_url = { role_arn = "arn:aws:iam::111111111111:role/alpha-dev-iot-jobs-presign", expires_in_sec = 3601 }
  }

  expect_failures = [var.presigned_url]
}

run "presigned_url_role_not_a_role_arn_rejected" {
  command = plan

  variables {
    presigned_url = { role_arn = "arn:aws:iam::111111111111:user/alpha" }
  }

  expect_failures = [var.presigned_url]
}

run "retry_above_10_rejected" {
  command = plan

  variables {
    retry = [{ failure_type = "FAILED", number_of_retries = 11 }]
  }

  expect_failures = [var.retry]
}

run "retry_negative_rejected" {
  command = plan

  variables {
    retry = [{ failure_type = "FAILED", number_of_retries = -1 }]
  }

  expect_failures = [var.retry]
}

run "retry_unknown_failure_type_rejected" {
  command = plan

  variables {
    retry = [{ failure_type = "REJECTED", number_of_retries = 1 }]
  }

  expect_failures = [var.retry]
}

run "rollout_both_kinds_rejected" {
  command = plan

  variables {
    rollout = {
      maximum_per_minute = 50
      exponential        = { base_rate_per_minute = 5, increment_factor = 2, number_of_succeeded_things = 10 }
    }
  }

  expect_failures = [var.rollout]
}

run "abort_percentage_above_100_rejected" {
  command = plan

  variables {
    abort = [{ failure_type = "FAILED", threshold_percentage = 101, min_number_of_executed_things = 5 }]
  }

  expect_failures = [var.abort]
}

run "abort_unknown_failure_type_rejected" {
  command = plan

  variables {
    abort = [{ failure_type = "CRASHED", threshold_percentage = 10, min_number_of_executed_things = 5 }]
  }

  expect_failures = [var.abort]
}

run "timeout_out_of_range_rejected" {
  command = plan

  variables {
    timeout_minutes = 10081
  }

  expect_failures = [var.timeout_minutes]
}

run "maintenance_window_not_cron_rejected" {
  command = plan

  variables {
    maintenance_windows = [{ start_time = "18:00", duration_minutes = 120 }]
  }

  expect_failures = [var.maintenance_windows]
}

run "maintenance_window_duration_out_of_range_rejected" {
  command = plan

  variables {
    maintenance_windows = [{ start_time = "cron(0 18 ? * MON-FRI *)", duration_minutes = 1431 }]
  }

  expect_failures = [var.maintenance_windows]
}
