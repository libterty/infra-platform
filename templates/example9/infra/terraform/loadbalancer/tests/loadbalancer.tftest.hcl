mock_provider "aws" {}

variables {
  project             = "cicd"
  env                 = "dev"
  expected_account_id = "111111111111"
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_cidr"]
  values = { insecure_value = "10.30.0.0/16" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/app_subnet_ids"]
  values = { insecure_value = "subnet-0000000000000000c,subnet-0000000000000000d" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts" }
}

# The group ID is unknown at plan time; the published keys are checked with this value.
override_module {
  target  = module.sg
  outputs = { security_group_ids = { alb = "sg-0000000000000000a" }, security_group_arns = { alb = "arn:aws:ec2:ap-northeast-1:111111111111:security-group/sg-0000000000000000a" } }
}

run "reads_only_network_and_foundation_keys" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      vpc_id          = "network/vpc_id"
      vpc_cidr        = "network/vpc_cidr"
      alert_topic_arn = "foundation/alert_topic_arn"
    } && local.ssm_input_lists == { app_subnet_ids = "network/app_subnet_ids" }
    error_message = "loadbalancer may read only the network keys and the alert topic (design 8.3)"
  }
}

# Design 8.1: an internal ALB in the app tier, HTTP:80 only.
run "internal_http_alb_in_the_app_tier" {
  command = plan

  assert {
    condition = (
      local.alb.name == "cicd-dev-alb" &&
      local.alb.internal &&
      local.alb.subnet_ids == tolist(["subnet-0000000000000000c", "subnet-0000000000000000d"]) &&
      local.alb.security_group_ids == ["sg-0000000000000000a"] &&
      local.alb.sns_topic_arns == ["arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts"]
    )
    error_message = "The ALB must be internal, in the app subnets, with the stack's own group and the alert topic"
  }

  assert {
    condition     = module.alb.listener_protocol == "HTTP" && local.listener_port == 80
    error_message = "Without a certificate the ALB serves the rules on HTTP:80"
  }

  assert {
    condition     = !strcontains(file("${path.module}/alb.tf"), "certificate_arn")
    error_message = "The template has no certificate; adding one turns the listener into HTTPS and breaks the security group rules"
  }
}

# The ALB is reachable from and talks to the VPC only; nothing is open to the internet.
run "security_group_stays_inside_the_vpc" {
  command = plan

  assert {
    condition     = keys(local.security_groups) == ["alb"]
    error_message = "loadbalancer creates only the ALB group; the api group belongs to application"
  }

  assert {
    condition = local.sg_rules == {
      alb_in_http_vpc = { security_group = "alb", type = "ingress", description = "HTTP from inside the VPC", from_port = 80, cidr_ipv4 = "10.30.0.0/16" }
      alb_out_app_vpc = { security_group = "alb", type = "egress", description = "to the api tasks", from_port = 8080, cidr_ipv4 = "10.30.0.0/16" }
    }
    error_message = "The ALB group may only accept HTTP:80 from the VPC CIDR and reach the app port inside the VPC CIDR"
  }
}

run "publishes_the_listener_and_the_group" {
  command = plan

  override_module {
    target = module.alb
    outputs = {
      listener_arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/cicd-dev-alb/0123456789abcdef/0123456789abcdef"
      listener_protocol = "HTTP"
      alb_dns_name      = "internal-cicd-dev-alb-123456789.ap-northeast-1.elb.amazonaws.com"
    }
  }

  assert {
    condition = local.published_strings == {
      listener_arn      = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/cicd-dev-alb/0123456789abcdef/0123456789abcdef"
      security_group_id = "sg-0000000000000000a"
    }
    error_message = "loadbalancer must publish listener_arn and security_group_id (design 8.3)"
  }

  assert {
    condition = module.ssm_publish.names == {
      listener_arn      = "/cicd/dev/loadbalancer/listener_arn"
      security_group_id = "/cicd/dev/loadbalancer/security_group_id"
    }
    error_message = "ssm-publish must write the keys under the loadbalancer path"
  }
}

run "app_port_out_of_range_rejected" {
  command = plan

  variables {
    app_port = 70000
  }

  expect_failures = [var.app_port]
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
    condition     = local.name_prefix == "cicd-dev" && local.ssm_prefix == "/cicd/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Cicd"
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
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "cicd-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
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
