# Run by scripts/validate.sh once per file in envs/examples/ with -var-file, so the examples cannot rot.
# Do not set variables other than certificate_arn here, they would hide the example values. certificate_arn is pinned
# per run because override values cannot read the example file; each run pairs it with the matching network decision.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alb_log_bucket_name"]
  values = { insecure_value = "alpha-dev-alb-logs-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_alb_id"]
  values = { insecure_value = "sg-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_public"]
  values = { insecure_value = "subnet-0pub1,subnet-0pub2" }
}

run "example_without_certificate_is_http" {
  command = plan

  variables {
    certificate_arn = null
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition     = module.alb.listener_protocol == "HTTP"
    error_message = "Without a certificate the listener protocol must be HTTP"
  }
}

run "example_with_certificate_is_https" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  assert {
    condition     = module.alb.listener_protocol == "HTTPS"
    error_message = "With a certificate the listener protocol must be HTTPS"
  }
}

run "example_settings_reach_the_alb" {
  command = plan

  variables {
    certificate_arn = null
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition     = var.access_logs_enabled == (local.alb_wiring.access_logs != null)
    error_message = "access_logs_enabled must decide whether access logs are configured"
  }

  assert {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be a valid ALB value"
  }
}
