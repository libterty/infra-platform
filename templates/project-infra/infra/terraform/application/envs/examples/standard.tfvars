# Standard production: autoscaling, health checks dropped from traces, 5% sampling, error and slow groups, a log alarm.
# Copy to envs/<env>.tfvars and adjust; not applied by itself.
# The 5% rate has no measured basis (design section 5.11); tune it with real traffic and cost.
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

services = {
  api = {
    image_tag      = "0000000"
    container_port = 8080
    desired_count  = 2
    max_capacity   = 10
    alb = {
      priority            = 100
      path_patterns       = ["/api/*"]
      requests_per_target = 300
    }
  }
  worker = {
    image_tag      = "0000000"
    container_port = 9000
    desired_count  = 2
    max_capacity   = 4
  }
}

xray_sampling_rules = {
  health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" } # drop health checks
  api    = { priority = 200, fixed_rate = 0.05, reservoir_size = 1, service_name = "alpha-prod-api" }
}

xray_groups = {
  errors = { filter_expression = "fault = true OR error = true" }
  slow   = { filter_expression = "responsetime > 3" }
}

# Fires when the application logs the pattern. Say what it means and what to check first.
log_alarms = {
  api = {
    audit_write_failed = {
      pattern     = "\"audit_write_failed\""
      metric_name = "AuditWriteFailed"
      description = "The api could not write an audit record. Check the database connection and the api task logs."
    }
  }
}
