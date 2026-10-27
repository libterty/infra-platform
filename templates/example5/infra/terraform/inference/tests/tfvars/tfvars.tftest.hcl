# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
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
  target = module.in.data.aws_ssm_parameter.this["network/subnet_ids_data"]
  values = { insecure_value = "subnet-0dat1,subnet-0dat2" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_name"]
  values = { insecure_value = "example-dev-ml-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_sagemaker_endpoint_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-sagemaker-endpoint" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["ml/model_package_group_name"]
  values = { insecure_value = "example-dev-models" }
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

# Design section 7.5: no endpoint in dev and sit until a model is approved.
run "tfvars_create_nothing" {
  command = plan

  assert {
    condition     = var.model_package_arn == null && length(module.endpoint) == 0 && length(module.alarms) == 0
    error_message = "dev and sit tfvars must not create an endpoint"
  }
}
