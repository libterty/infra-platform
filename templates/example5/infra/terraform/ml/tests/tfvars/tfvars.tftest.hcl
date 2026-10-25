# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/ml_bucket_name"]
  values = { insecure_value = "example-dev-ml-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["storage/model_approved_queue_arn"]
  values = { insecure_value = "arn:aws:sqs:ap-northeast-1:111111111111:example-dev-model-approved" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_sagemaker_pipeline_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-sagemaker-pipeline" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam-base/role_scheduler_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/example-dev-scheduler" }
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

# Design section 7.5 and K24: dev does not train every week, sit does.
run "tfvars_schedule_state_matches_the_env" {
  command = plan

  assert {
    condition     = var.training_schedule_state == (var.env == "dev" ? "DISABLED" : "ENABLED")
    error_message = "The weekly training schedule must be DISABLED in dev and ENABLED in sit"
  }
}
