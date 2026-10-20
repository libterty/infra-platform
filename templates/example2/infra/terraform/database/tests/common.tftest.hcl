# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {}

mock_provider "random" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan.
  engine_version        = "16.6"
  db_instance_class     = "db.t4g.medium"
  connections_threshold = 300
  redis = {
    "rate-limit" = { node_type = "cache.t4g.small" }
    "stream"     = { node_type = "cache.t4g.small" }
  }
}

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
