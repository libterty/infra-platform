# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan.
  eval_batch_model_id = "anthropic.claude-sonnet-4-5-20250929-v1:0"
}

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

run "dev_accepts_its_account" {
  command = plan

  assert {
    condition     = local.name_prefix == "example-dev"
    error_message = "dev with the dev account must plan, and name_prefix must be <project>-<env>"
  }

  assert {
    condition     = local.ssm_prefix == "/example/dev" && local.shared_ssm_prefix == "/example-shared/dev"
    error_message = "ssm_prefix and shared_ssm_prefix must follow the two-tree layout"
  }
}

run "sit_accepts_its_account" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "example-sit"
    error_message = "sit with the sit account must plan"
  }
}

run "rejects_an_account_of_another_env" {
  command = plan

  variables {
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "rejects_an_env_without_an_account" {
  command = plan

  variables {
    env = "other"
  }

  expect_failures = [var.expected_account_id]
}

run "rejects_a_malformed_env" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "rejects_a_deploy_role_in_another_account" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "accepts_a_deploy_role_in_the_same_account" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn != ""
    error_message = "A role in expected_account_id must be accepted"
  }
}
