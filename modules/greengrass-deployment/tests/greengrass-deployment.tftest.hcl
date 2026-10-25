mock_provider "awscc" {}

variables {
  name       = "alpha-dev-fleet"
  target_arn = "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet"

  components = {
    "aws.greengrass.Nucleus" = { version = "2.14.3" }
    "com.example.Inference" = {
      version  = "1.0.0"
      merge    = { model = { path = "/greengrass/v2/work/model.onnx", threshold = 0.8 }, topics = ["alpha/dev/sensors"] }
      reset    = ["/legacy"]
      run_with = { posix_user = "ggc_user:ggc_group" }
    }
  }

  rollout = { maximum_per_minute = 50 }

  abort = [
    { failure_type = "FAILED", threshold_percentage = 10, min_number_of_executed_things = 5 },
  ]
}

# ---- positive -------------------------------------------------------------------------------------------------

run "thing_group_target_with_components" {
  command = plan

  assert {
    condition     = awscc_greengrassv2_deployment.this.target_arn == "arn:aws:iot:ap-northeast-1:111111111111:thinggroup/alpha-dev-fleet"
    error_message = "The target ARN must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_name == "alpha-dev-fleet"
    error_message = "The deployment name must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.components["aws.greengrass.Nucleus"].component_version == "2.14.3"
    error_message = "The pinned nucleus version must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.components["com.example.Inference"].component_version == "1.0.0"
    error_message = "Component versions must be passed through"
  }
}

run "merge_is_json_encoded" {
  command = plan

  assert {
    condition     = jsondecode(awscc_greengrassv2_deployment.this.components["com.example.Inference"].configuration_update.merge).model.threshold == 0.8
    error_message = "merge must be JSON-encoded by the module"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.components["com.example.Inference"].configuration_update.reset == tolist(["/legacy"])
    error_message = "reset must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.components["com.example.Inference"].run_with.posix_user == "ggc_user:ggc_group"
    error_message = "posix_user must be passed through"
  }
}

run "merge_shapes_may_differ_between_components" {
  command = plan

  variables {
    components = {
      "com.example.Inference" = { version = "1.0.0", merge = { threshold = 0.8 } }
      "com.example.Collector" = { version = "2.0.0", merge = { topics = ["a", "b"], interval = { seconds = 5 } } }
    }
  }

  assert {
    condition     = jsondecode(awscc_greengrassv2_deployment.this.components["com.example.Collector"].configuration_update.merge).interval.seconds == 5
    error_message = "Components with differently shaped merge objects must be accepted"
  }
}

run "thing_target" {
  command = plan

  variables {
    target_arn = "arn:aws:iot:ap-northeast-1:111111111111:thing/alpha-dev-core-001"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.target_arn == "arn:aws:iot:ap-northeast-1:111111111111:thing/alpha-dev-core-001"
    error_message = "A thing ARN must be accepted as target"
  }
}

run "deployment_policy_defaults" {
  command = plan

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.failure_handling_policy == "ROLLBACK"
    error_message = "failure handling must default to ROLLBACK"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.component_update_policy.action == "NOTIFY_COMPONENTS"
    error_message = "component update must default to NOTIFY_COMPONENTS"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.component_update_policy.timeout_in_seconds == 60
    error_message = "component update timeout must default to 60 seconds"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.configuration_validation_policy.timeout_in_seconds == 30
    error_message = "configuration validation timeout must default to 30 seconds"
  }
}

run "rollout_maximum_per_minute_and_abort" {
  command = plan

  assert {
    condition     = awscc_greengrassv2_deployment.this.iot_job_configuration.job_executions_rollout_config.maximum_per_minute == 50
    error_message = "maximum_per_minute must be passed through"
  }

  assert {
    condition = awscc_greengrassv2_deployment.this.iot_job_configuration.abort_config.criteria_list == tolist([{
      action                        = "CANCEL"
      failure_type                  = "FAILED"
      threshold_percentage          = 10
      min_number_of_executed_things = 5
    }])
    error_message = "abort criteria must be passed through with action CANCEL"
  }
}

run "exponential_rollout_and_timeout" {
  command = plan

  variables {
    rollout = {
      exponential = { base_rate_per_minute = 5, increment_factor = 2, number_of_succeeded_things = 10 }
    }
    in_progress_timeout_minutes = 120
    failure_handling            = "DO_NOTHING"
    component_update            = { action = "SKIP_NOTIFY_COMPONENTS", timeout_seconds = 120 }
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.iot_job_configuration.job_executions_rollout_config.exponential_rate.base_rate_per_minute == 5 && awscc_greengrassv2_deployment.this.iot_job_configuration.job_executions_rollout_config.exponential_rate.increment_factor == 2
    error_message = "exponential rate must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.iot_job_configuration.job_executions_rollout_config.exponential_rate.rate_increase_criteria.number_of_succeeded_things == 10
    error_message = "number_of_succeeded_things must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.iot_job_configuration.timeout_config.in_progress_timeout_in_minutes == 120
    error_message = "in-progress timeout must be passed through"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.failure_handling_policy == "DO_NOTHING"
    error_message = "failure handling must be configurable"
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.deployment_policies.component_update_policy.action == "SKIP_NOTIFY_COMPONENTS"
    error_message = "component update action must be configurable"
  }
}

run "tags_are_a_map_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha", Environment = "dev" }
  }

  assert {
    condition     = awscc_greengrassv2_deployment.this.tags == tomap({ Project = "alpha", Environment = "dev", Name = "alpha-dev-fleet" })
    error_message = "Tags must be a map of the given tags plus Name"
  }
}

run "deployment_id_after_apply" {
  override_resource {
    target = awscc_greengrassv2_deployment.this
    values = {
      deployment_id = "a1b2c3d4-5678-90ab-cdef-111111111111"
    }
  }

  assert {
    condition     = output.deployment_id == "a1b2c3d4-5678-90ab-cdef-111111111111"
    error_message = "deployment_id output must be the deployment id"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "target_not_thing_or_group_rejected" {
  command = plan

  variables {
    target_arn = "arn:aws:iot:ap-northeast-1:111111111111:policy/alpha-dev-core"
  }

  expect_failures = [var.target_arn]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "no_components_rejected" {
  command = plan

  variables {
    components = {}
  }

  expect_failures = [var.components]
}

run "component_version_not_semver_rejected" {
  command = plan

  variables {
    components = { "com.example.Inference" = { version = "latest" } }
  }

  expect_failures = [var.components]
}

run "component_without_version_rejected" {
  command = plan

  variables {
    components = { "com.example.Inference" = { merge = { a = 1 } } }
  }

  expect_failures = [var.components]
}

run "unknown_component_field_rejected" {
  command = plan

  variables {
    components = { "com.example.Inference" = { version = "1.0.0", windows_user = "Administrator" } }
  }

  expect_failures = [var.components]
}

run "merge_not_an_object_rejected" {
  command = plan

  variables {
    components = { "com.example.Inference" = { version = "1.0.0", merge = "{\"a\":1}" } }
  }

  expect_failures = [var.components]
}

run "invalid_posix_user_rejected" {
  command = plan

  variables {
    components = { "com.example.Inference" = { version = "1.0.0", run_with = { posix_user = "root; rm -rf /" } } }
  }

  expect_failures = [var.components]
}

run "unknown_failure_handling_rejected" {
  command = plan

  variables {
    failure_handling = "IGNORE"
  }

  expect_failures = [var.failure_handling]
}

run "unknown_component_update_action_rejected" {
  command = plan

  variables {
    component_update = { action = "FORCE" }
  }

  expect_failures = [var.component_update]
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

run "rollout_neither_kind_rejected" {
  command = plan

  variables {
    rollout = {}
  }

  expect_failures = [var.rollout]
}

run "rollout_increment_factor_out_of_range_rejected" {
  command = plan

  variables {
    rollout = {
      exponential = { base_rate_per_minute = 5, increment_factor = 6, number_of_succeeded_things = 10 }
    }
  }

  expect_failures = [var.rollout]
}

run "abort_empty_rejected" {
  command = plan

  variables {
    abort = []
  }

  expect_failures = [var.abort]
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

run "in_progress_timeout_out_of_range_rejected" {
  command = plan

  variables {
    in_progress_timeout_minutes = 0
  }

  expect_failures = [var.in_progress_timeout_minutes]
}
