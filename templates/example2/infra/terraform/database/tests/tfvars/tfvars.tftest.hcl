# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

mock_provider "random" {}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      db_sg_id        = "sg-0aaaaaaa00000004"
      db_proxy_sg_id  = "sg-0aaaaaaa00000005"
      cache_sg_id     = "sg-0aaaaaaa00000006"
    }
    lists = {
      db_subnet_ids = ["subnet-0ddddddd00000001", "subnet-0ddddddd00000002"]
    }
  }
}

override_data {
  target = data.aws_kms_alias.secretsmanager
  values = { target_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
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
