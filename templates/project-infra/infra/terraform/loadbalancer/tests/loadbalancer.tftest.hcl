mock_provider "aws" {}

variables {
  project             = "alpha"
  env                 = "dev"
  expected_account_id = "111111111111"
}

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

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
  values = { insecure_value = "{\"enabled\":false}" }
}

run "reads_only_listed_keys" {
  command = plan

  assert {
    condition = (
      local.ssm_input_strings == {
        alarm_topic_arn     = "foundation/alarm_topic_arn"
        alb_log_bucket_name = "foundation/alb_log_bucket_name"
        sg_alb_id           = "network/sg_alb_id"
        alb_https           = "network/alb_https"
      } &&
      local.ssm_input_lists == { subnet_ids_public = "network/subnet_ids_public" }
    )
    error_message = "loadbalancer must read the alarm topic, the ALB log bucket, the ALB security group, the public subnets and the TLS decision"
  }
}

run "publishes_under_stack_path" {
  command = plan

  assert {
    condition = module.ssm_publish.names == {
      alb_arn           = "/alpha/dev/loadbalancer/alb_arn"
      alb_arn_suffix    = "/alpha/dev/loadbalancer/alb_arn_suffix"
      alb_dns_name      = "/alpha/dev/loadbalancer/alb_dns_name"
      alb_zone_id       = "/alpha/dev/loadbalancer/alb_zone_id"
      listener_arn      = "/alpha/dev/loadbalancer/listener_arn"
      listener_protocol = "/alpha/dev/loadbalancer/listener_protocol"
    }
    error_message = "ssm-publish must write the six ALB keys under the loadbalancer path"
  }
}

run "publishes_listener_keys" {
  command = plan

  override_module {
    target = module.alb
    outputs = {
      alb_arn           = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev-alb/0123456789abcdef"
      alb_arn_suffix    = "app/alpha-dev-alb/0123456789abcdef"
      alb_dns_name      = "alpha-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id       = "Z14GRHDCWA56QT"
      listener_arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev-alb/0123456789abcdef/fedcba9876543210"
      listener_protocol = "HTTP"
    }
  }

  assert {
    condition = local.published_strings == {
      alb_arn           = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:loadbalancer/app/alpha-dev-alb/0123456789abcdef"
      alb_arn_suffix    = "app/alpha-dev-alb/0123456789abcdef"
      alb_dns_name      = "alpha-dev-alb-123.ap-northeast-1.elb.amazonaws.com"
      alb_zone_id       = "Z14GRHDCWA56QT"
      listener_arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/alpha-dev-alb/0123456789abcdef/fedcba9876543210"
      listener_protocol = "HTTP"
    }
    error_message = "The six published keys must come from the matching alb module outputs"
  }
}

run "wired_from_upstream" {
  command = plan

  assert {
    condition = (
      tolist(local.alb_wiring.subnet_ids) == tolist(["subnet-0pub1", "subnet-0pub2"]) &&
      local.alb_wiring.security_group_ids == ["sg-0123456789abcdef0"] &&
      local.alb_wiring.sns_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"]
    )
    error_message = "Public subnets, the ALB security group and the alarm topic must come from the upstream stacks"
  }
}

run "access_logs_off_by_default" {
  command = plan

  assert {
    condition     = local.alb_wiring.access_logs == null
    error_message = "Access logs must stay off unless access_logs_enabled is set"
  }
}

run "access_logs_use_the_foundation_bucket" {
  command = plan

  variables {
    access_logs_enabled = true
  }

  assert {
    condition     = local.alb_wiring.access_logs == { bucket = "alpha-dev-alb-logs-111111111111", prefix = "alpha-dev" }
    error_message = "Access logs must go to the bucket name published by foundation"
  }
}

run "tls_must_match_network_certificate_missing" {
  command = plan

  override_data {
    target = module.in.data.aws_ssm_parameter.this["network/alb_https"]
    values = { insecure_value = "{\"enabled\":true}" }
  }

  expect_failures = [terraform_data.tls_matches_network]
}

run "tls_must_match_network_certificate_unexpected" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:ap-northeast-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [terraform_data.tls_matches_network]
}

run "tls_matches_network_https" {
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
    error_message = "With a certificate and alb_https true the ALB must serve HTTPS"
  }
}

run "tls_matches_network_http" {
  command = plan

  assert {
    condition     = module.alb.listener_protocol == "HTTP"
    error_message = "Without a certificate and with alb_https false the ALB must serve HTTP only"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "alpha-dev" && local.ssm_prefix == "/alpha/dev"
    error_message = "A valid env must produce the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Alpha"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "prod"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "alpha-prod" && contains(local.accounts_by_env["prod"], var.expected_account_id)
    error_message = "A prod account with env prod must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
