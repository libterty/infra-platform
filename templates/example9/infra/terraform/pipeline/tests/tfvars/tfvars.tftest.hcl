# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/artifact_bucket_name"]
  values = { insecure_value = "cicd-dev-artifacts-111111111111" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:cicd-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/connection_arn"]
  values = { insecure_value = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/api_deploy_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-api-deploy-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/fn_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-fn-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/web_build_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-web-build-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/web_invalidate_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-web-invalidate-codebuild" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/pipeline_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/cicd-dev-pipeline" }
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

# Design 8.4 and K6.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.repository == "example-org/example-app" && var.branch == (var.env == "dev" ? "develop" : "main")
    error_message = "dev deploys develop and sit deploys main of example-org/example-app"
  }

  assert {
    condition     = var.approval_required == (var.env == "sit")
    error_message = "Only sit has a manual approval before Deploy"
  }

  assert {
    condition     = var.fn_deploy_strategy == (var.env == "dev" ? "AllAtOnce" : "Canary10Percent5Minutes")
    error_message = "fn deploys AllAtOnce in dev and Canary10Percent5Minutes in sit"
  }

  assert {
    condition     = var.log_retention_days == (var.env == "dev" ? 30 : 90)
    error_message = "Build logs must be kept 30 days in dev and 90 days in sit"
  }
}
