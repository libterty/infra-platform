# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

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

# The application stack's tfvars use the same port; the ALB egress only opens this one.
run "tfvars_app_port_matches_application" {
  command = plan

  assert {
    condition     = var.app_port == 8080
    error_message = "app_port must be 8080, the value application/envs/<env>.tfvars uses"
  }
}

run "tfvars_deletion_protection_only_off_in_dev" {
  command = plan

  assert {
    condition     = var.deletion_protection == (var.env != "dev")
    error_message = "Deletion protection is off in dev only"
  }
}
