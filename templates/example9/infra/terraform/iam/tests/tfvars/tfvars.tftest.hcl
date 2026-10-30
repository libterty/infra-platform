# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
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
  target = module.in.data.aws_ssm_parameter.this["foundation/connection_arn"]
  values = { insecure_value = "arn:aws:codeconnections:ap-northeast-1:111111111111:connection/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/api_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-api" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/fn_repository_url"]
  values = { insecure_value = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/cicd-dev-fn" }
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
    condition = (
      local.roles.pipeline.name == "${var.project}-${var.env}-pipeline" &&
      local.api_service_arn == "arn:aws:ecs:ap-northeast-1:${var.expected_account_id}:service/${var.project}-${var.env}/${var.project}-${var.env}-api" &&
      alltrue([for r in values(local.roles) : length(r.name) <= 64])
    )
    error_message = "Role names and ARNs must be built from the tfvars project, env and account, and fit IAM's 64 characters"
  }
}
