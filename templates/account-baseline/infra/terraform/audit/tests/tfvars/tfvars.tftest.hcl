# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/trail_bucket_name"]
  values = { insecure_value = "baseline-dev-trail-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/config_bucket_name"]
  values = { insecure_value = "baseline-dev-config-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/config_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/baseline-dev-config-recorder" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/trail_logs_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/baseline-dev-trail-logs" }
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

run "tfvars_trail_log_retention_follows_the_env" {
  command = plan

  assert {
    condition     = var.trail_log_retention_days == (var.env == "dev" ? 90 : 365)
    error_message = "The trail log group keeps 90 days in dev and 365 days in sit (design 8.3)"
  }

  assert {
    condition     = local.trail_log_group_name == "/aws/cloudtrail/${var.project}-${var.env}" && local.trail.name == "${var.project}-${var.env}-trail"
    error_message = "The trail and its log group must be named after the tfvars project and env"
  }
}
