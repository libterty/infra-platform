# High traffic: wider autoscaling range, 1% sampling, health checks dropped. Copy to envs/<env>.tfvars and adjust;
# not applied by itself. The sampling rate has no measured basis (design section 5.11).
project             = "alpha"
env                 = "prod"
expected_account_id = "222222222222"

services = {
  api = {
    image_tag      = "0000000"
    container_port = 8080
    cpu            = 1024
    memory         = 2048
    desired_count  = 10
    max_capacity   = 40
    alb = {
      priority            = 100
      path_patterns       = ["/api/*"]
      requests_per_target = 300
    }
  }
  worker = {
    image_tag      = "0000000"
    container_port = 9000
    desired_count  = 4
    max_capacity   = 12
  }
}

xray_sampling_rules = {
  health = { priority = 100, fixed_rate = 0, reservoir_size = 0, url_path = "/health" }
  api    = { priority = 200, fixed_rate = 0.01, reservoir_size = 1, service_name = "alpha-prod-api" }
}

xray_groups = {
  errors = { filter_expression = "fault = true OR error = true" }
  slow   = { filter_expression = "responsetime > 3" }
}

log_alarms = {
  api = {
    audit_write_failed = {
      pattern     = "\"audit_write_failed\""
      metric_name = "AuditWriteFailed"
      description = "The api could not write an audit record. Check the database connection and the api task logs."
    }
    rate_limit_fail_open = {
      pattern     = "\"rate_limit_fail_open\""
      metric_name = "RateLimitFailOpen"
      description = "The rate limiter failed open and is letting requests through. Check the cache connection."
    }
  }
}
