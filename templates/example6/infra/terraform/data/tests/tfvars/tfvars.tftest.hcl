# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
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

# Design 8.3: dev keeps 7 days of PITR without deletion protection, sit 35 days with it.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.point_in_time_recovery_days == (var.env == "dev" ? 7 : 35)
    error_message = "PITR must be 7 days in dev and 35 days in sit"
  }

  assert {
    condition     = var.deletion_protection == (var.env != "dev")
    error_message = "Deletion protection must be off in dev and on in sit"
  }
}
