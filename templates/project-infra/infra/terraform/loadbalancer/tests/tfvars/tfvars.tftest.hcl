# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# test override values cannot read tfvars values, so each run pins certificate_arn together with the network decision
# it is consistent with. The sibling-file run below checks that the two tfvars files agree.
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

run "tfvars_plan_as_https_with_a_certificate" {
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
    error_message = "With a certificate the ALB must serve HTTPS"
  }

  assert {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout in tfvars must be a valid ALB value"
  }
}

run "tfvars_plan_as_http_without_a_certificate" {
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
    error_message = "Without a certificate the ALB must serve HTTP only"
  }
}

# Two stacks, two tfvars files, one decision: a certificate here iff network says https = true there.
run "certificate_decision_agrees_with_network_tfvars" {
  command = plan

  variables {
    certificate_arn = null
  }

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
    values = { insecure_value = "{\"enabled\":false}" }
  }

  assert {
    condition = (
      length(regexall("(?m)^\\s*certificate_arn\\s*=", file("${path.module}/envs/${var.env}.tfvars"))) > 0
      ) == (
      length(regexall("https\\s*=\\s*true", file("${path.module}/../network/envs/${var.env}.tfvars"))) > 0
    )
    error_message = "certificate_arn must be set in this tfvars file exactly when network/envs/<env>.tfvars says alb_ingress.https = true"
  }
}
