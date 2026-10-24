# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, network and iam-base publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_redshift_id"]
  values = { insecure_value = "sg-0aaaaaaa00000004" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_redshift_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-placeholder-redshift" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dda0001,subnet-0dda0002" }
}

run "tfvars_build_exactly_one_redshift" {
  command = plan

  assert {
    condition     = length(module.serverless) + length(module.provisioned) == 1
    error_message = "Each tfvars file must build exactly one Redshift module"
  }

  assert {
    condition     = terraform_data.warehouse_mode_guard.triggers_replace == var.warehouse_mode
    error_message = "The guard must be bound to warehouse_mode"
  }
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

# Design K16 and section 7.5: dev and sit run Serverless, base 4 RPU; max 8 and 100 RPU-hours a month in dev, 16 and 200 in sit.
run "tfvars_serverless_limits_match_the_env" {
  command = plan

  assert {
    condition     = var.warehouse_mode == "serverless" && length(module.serverless) == 1
    error_message = "dev and sit must default to serverless (design K16)"
  }

  assert {
    condition = (
      var.serverless.base_capacity == 4 &&
      var.serverless.max_capacity == (var.env == "dev" ? 8 : 16) &&
      var.serverless.usage_limit_rpu_hours == (var.env == "dev" ? 100 : 200)
    )
    error_message = "Serverless must be base 4 with max 8 and 100 RPU-hours in dev, max 16 and 200 in sit (design section 7.5)"
  }
}
