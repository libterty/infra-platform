# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/fn_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/vpc_id"]
  values = { insecure_value = "vpc-0123456789abcdef0" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/app_subnet_ids"]
  values = { insecure_value = "subnet-0000000000000000c,subnet-0000000000000000d" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_execution_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-execution" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_task_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-task" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/fn_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-fn" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/listener_arn"]
  values = { insecure_value = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:listener/app/cicd-dev-alb/0123456789abcdef/0123456789abcdef" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["loadbalancer/security_group_id"]
  values = { insecure_value = "sg-0000000000000000a" }
}

run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

# Design 8.4.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.api_desired_count == (var.env == "dev" ? 1 : 2)
    error_message = "The api service runs 1 task in dev and 2 in sit"
  }

  assert {
    condition     = var.log_retention_days == (var.env == "dev" ? 30 : 90)
    error_message = "Logs must be kept 30 days in dev and 90 days in sit"
  }
}

run "tfvars_app_port_matches_loadbalancer" {
  command = plan

  assert {
    condition     = var.app_port == 8080
    error_message = "app_port must be 8080, the value loadbalancer/envs/<env>.tfvars uses"
  }
}

# K10: the tag someone pushes by hand before the first apply.
run "tfvars_use_the_bootstrap_tag" {
  command = plan

  assert {
    condition     = var.api_bootstrap_image_tag == "bootstrap" && var.fn_bootstrap_image_tag == "bootstrap"
    error_message = "Both bootstrap tags must be bootstrap, the tag the comment in the tfvars tells people to push"
  }
}
