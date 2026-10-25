# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}
mock_provider "awscc" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["pki/ca"]
  values = { insecure_value = "{\"enabled\":false}" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ota_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ota-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_provisioning_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-provisioning" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_logging_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-logging" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_audit_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-audit" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_iot_mitigation_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-iot-mitigation" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_greengrass_tes_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-greengrass-tes" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_ota_presign_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-ota-presign" }
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

  assert {
    condition     = split(":", var.ota_signing_certificate_arn)[4] == var.expected_account_id
    error_message = "The signing certificate placeholder must be in the env's account"
  }
}

# Design K9 and section 7.5: dev and sit set the account-level settings with WARN logging and the audit.
run "tfvars_set_the_account_level_settings" {
  command = plan

  assert {
    condition     = var.account_settings != null && var.account_settings.log_level == "WARN" && length(module.account_settings) == 1
    error_message = "dev and sit must set account_settings with log level WARN (a second project in the account sets null)"
  }

  assert {
    condition     = var.device_defender_audit != null && local.audit != null
    error_message = "dev and sit must set device_defender_audit (a second project in the account sets null)"
  }
}

# Design section 7.5: dev rolls out 10 devices per minute and aborts at 10 % failures, sit 20 and 5 %.
run "tfvars_ota_rollout_matches_the_env" {
  command = plan

  assert {
    condition     = var.ota_rollout == (var.env == "dev" ? { maximum_per_minute = 10, abort_threshold_percentage = 10 } : { maximum_per_minute = 20, abort_threshold_percentage = 5 })
    error_message = "dev must roll out 10 per minute aborting at 10 %, sit 20 per minute aborting at 5 %"
  }
}
