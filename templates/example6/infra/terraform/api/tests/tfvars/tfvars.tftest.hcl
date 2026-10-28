# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/api_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/api-key-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/origin_verify_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/origin-verify-GhIjKl" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["auth/issuer_url"]
  values = { insecure_value = "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_AbCdEfGhI" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["auth/spa_client_id"]
  values = { insecure_value = "1example23456789abcdefghij" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["data/table_name"]
  values = { insecure_value = "example-dev-app" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-api-lambda" }
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

# Design 8.3.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.api_reserved_concurrency == (var.env == "dev" ? 10 : 50)
    error_message = "Reserved concurrency must be 10 in dev and 50 in sit"
  }

  assert {
    condition     = var.api_throttling == (var.env == "dev" ? { rate_limit = 50, burst_limit = 100 } : { rate_limit = 200, burst_limit = 400 })
    error_message = "Throttling must be 50/100 in dev and 200/400 in sit"
  }

  assert {
    condition     = var.log_retention_days == (var.env == "dev" ? 30 : 90)
    error_message = "Logs must be kept 30 days in dev and 90 days in sit"
  }

  assert {
    condition     = var.api_image_tag != "latest"
    error_message = "The image tag must be explicit"
  }
}

# The web stack sends this header; both tfvars files must name it the same.
run "tfvars_origin_verify_header_name_matches_web" {
  command = plan

  assert {
    condition     = var.origin_verify_header_name == "X-Origin-Verify"
    error_message = "origin_verify_header_name must be X-Origin-Verify, the name web/envs/<env>.tfvars uses"
  }
}
