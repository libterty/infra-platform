# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      agent_runtimes                 = "[\"agent\"]"
      ecr_repository_arns = jsonencode({
        api    = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-api"
        worker = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-worker"
        agent  = "arn:aws:ecr:ap-northeast-1:111111111111:repository/example-agent"
      })
    }
    lists = {}
  }
}

override_data {
  target = data.aws_kms_alias.secretsmanager
  values = { target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab" }
}

run "tfvars_pair_env_with_a_registered_account" {
  command = plan

  assert {
    condition     = var.project == "example"
    error_message = "Every tfvars file of the template uses the placeholder project name"
  }

  assert {
    condition     = contains(local.accounts_by_env[var.env], var.expected_account_id)
    error_message = "expected_account_id in tfvars must be one of the accounts registered for env in common.tf"
  }

  assert {
    condition     = var.deploy_role_arn == ""
    error_message = "The template ships with an empty deploy_role_arn so it runs as the caller"
  }
}
