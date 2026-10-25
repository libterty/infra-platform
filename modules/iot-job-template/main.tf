resource "awscc_iot_job_template" "this" {
  job_template_id = var.job_template_id
  description     = var.description
  document        = var.document == null ? null : jsonencode(var.document)
  document_source = var.document_source

  presigned_url_config = var.presigned_url == null ? null : {
    role_arn       = var.presigned_url.role_arn
    expires_in_sec = var.presigned_url.expires_in_sec
  }

  job_executions_rollout_config = var.rollout == null ? null : {
    maximum_per_minute = var.rollout.maximum_per_minute
    exponential_rollout_rate = var.rollout.exponential == null ? null : {
      base_rate_per_minute = var.rollout.exponential.base_rate_per_minute
      increment_factor     = var.rollout.exponential.increment_factor
      rate_increase_criteria = {
        number_of_succeeded_things = var.rollout.exponential.number_of_succeeded_things
      }
    }
  }

  abort_config = length(var.abort) == 0 ? null : {
    criteria_list = [
      for a in var.abort : {
        action                        = "CANCEL"
        failure_type                  = a.failure_type
        threshold_percentage          = a.threshold_percentage
        min_number_of_executed_things = a.min_number_of_executed_things
      }
    ]
  }

  job_executions_retry_config = length(var.retry) == 0 ? null : {
    retry_criteria_list = [
      for r in var.retry : {
        failure_type      = r.failure_type
        number_of_retries = r.number_of_retries
      }
    ]
  }

  timeout_config = var.timeout_minutes == null ? null : {
    in_progress_timeout_in_minutes = var.timeout_minutes
  }

  maintenance_windows = length(var.maintenance_windows) == 0 ? null : [
    for w in var.maintenance_windows : {
      start_time          = w.start_time
      duration_in_minutes = w.duration_minutes
    }
  ]

  tags = [for k, v in merge(var.tags, { Name = var.job_template_id }) : { key = k, value = v }]
}
