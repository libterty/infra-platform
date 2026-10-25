locals {
  components = {
    for name, c in var.components : name => {
      component_version = c.version
      configuration_update = try(c.merge, null) == null && try(c.reset, null) == null ? null : {
        merge = try(c.merge, null) == null ? null : jsonencode(c.merge)
        reset = try(c.reset, null) == null ? null : [for r in c.reset : tostring(r)]
      }
      run_with = try(c.run_with, null) == null ? null : {
        posix_user = c.run_with.posix_user
      }
    }
  }
}

resource "awscc_greengrassv2_deployment" "this" {
  deployment_name = var.name
  target_arn      = var.target_arn
  components      = local.components

  deployment_policies = {
    failure_handling_policy = var.failure_handling
    component_update_policy = {
      action             = var.component_update.action
      timeout_in_seconds = var.component_update.timeout_seconds
    }
    configuration_validation_policy = {
      timeout_in_seconds = var.configuration_validation_timeout_seconds
    }
  }

  iot_job_configuration = {
    job_executions_rollout_config = {
      maximum_per_minute = var.rollout.maximum_per_minute
      exponential_rate = var.rollout.exponential == null ? null : {
        base_rate_per_minute = var.rollout.exponential.base_rate_per_minute
        increment_factor     = var.rollout.exponential.increment_factor
        rate_increase_criteria = {
          number_of_succeeded_things = var.rollout.exponential.number_of_succeeded_things
        }
      }
    }

    abort_config = {
      criteria_list = [
        for a in var.abort : {
          action                        = "CANCEL"
          failure_type                  = a.failure_type
          threshold_percentage          = a.threshold_percentage
          min_number_of_executed_things = a.min_number_of_executed_things
        }
      ]
    }

    timeout_config = var.in_progress_timeout_minutes == null ? null : {
      in_progress_timeout_in_minutes = var.in_progress_timeout_minutes
    }
  }

  tags = merge(var.tags, { Name = var.name })
}
