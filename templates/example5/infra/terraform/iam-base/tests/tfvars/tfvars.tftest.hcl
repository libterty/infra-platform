# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what foundation, network and storage publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alarm_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/sg_sagemaker_id"]
  values = { insecure_value = "sg-0aaaaaaa00000003" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_app"]
  values = { insecure_value = "subnet-0app1,subnet-0app2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/stream_arn"]
  values = { insecure_value = "arn:aws:kinesis:ap-northeast-1:111111111111:stream/example-dev-telemetry" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/rule_errors_queue_arn"]
  values = { insecure_value = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-rule-errors" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/greengrass_artifacts_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-greengrass-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ota_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ota-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_arn"]
  values = { insecure_value = "arn:aws:s3:::example-dev-ml-artifacts-111111111111" }
}

run "tfvars_build_the_eleven_roles" {
  command = plan

  assert {
    condition     = length(module.role) == 11
    error_message = "The tfvars must build the eleven roles"
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
