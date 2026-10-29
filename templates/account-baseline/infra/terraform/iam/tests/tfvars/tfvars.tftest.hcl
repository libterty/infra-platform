# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/config_bucket_name"]
  values = { insecure_value = "baseline-dev-config-111111111111" }
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

run "tfvars_names_and_arns_follow_the_env" {
  command = plan

  assert {
    condition     = local.service_roles.config.name == "${var.project}-${var.env}-config-recorder" && local.trail_log_group_arn == "arn:aws:logs:ap-northeast-1:${var.expected_account_id}:log-group:/aws/cloudtrail/${var.project}-${var.env}"
    error_message = "The role names and the log group ARN must be built from the tfvars project, env and account"
  }
}
