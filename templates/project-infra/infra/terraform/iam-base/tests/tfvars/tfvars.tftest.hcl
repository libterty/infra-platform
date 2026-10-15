# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/0000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/app_secret_arn"]
  values = { insecure_value = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:alpha-dev/app-AbCdEf" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/mirrored_images"]
  values = { insecure_value = "[]" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["containerimage/services"]
  values = { insecure_value = "api,worker" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_api_arn"]
  values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-api" }
}

override_data {
  target = module.in_services.data.aws_ssm_parameter.this["containerimage/ecr_worker_arn"]
  values = { insecure_value = "arn:aws:ecr:ap-northeast-1:111111111111:repository/alpha-dev-worker" }
}

run "tfvars_create_the_three_roles" {
  command = plan

  assert {
    condition     = length(module.role) == 3
    error_message = "The three roles must be created in every environment"
  }

  assert {
    condition     = alltrue([for r in values(local.roles) : startswith(r.name, "${var.project}-${var.env}-")])
    error_message = "Role names must carry the project and env"
  }
}
