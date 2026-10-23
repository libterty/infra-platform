# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan. The value is a throwaway for the tests.
  origin_verify_header_name  = "X-Origin-Verify"
  origin_verify_header_value = "test-only-origin-secret"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id              = "vpc-0123456789abcdef0"
      alb_sg_id           = "sg-0123456789abcdef0"
      alarm_topic_arn     = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      ecr_repository_urls = "{}"
    }
    lists = {
      public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
    }
  }
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
