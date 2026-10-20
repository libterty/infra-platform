# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      alarm_topic_arn                = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-private-AbCdEf"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/signing-public-GhIjKl"
      agent_runtimes                 = "[\"agent\"]"
      ecr_repository_urls            = "{\"api\":\"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api\"}"
      vpc_id                         = "vpc-0aaaaaaa00000001"
      alb_sg_id                      = "sg-0aaaaaaa00000001"
      app_sg_id                      = "sg-0aaaaaaa00000002"
      agent_sg_id                    = "sg-0aaaaaaa00000003"
      bastion_sg_id                  = "sg-0aaaaaaa00000004"
      db_proxy_endpoint              = "example-dev.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint      = "rl.example.cache.amazonaws.com:6379"
      stream_redis_endpoint          = "st.example.cache.amazonaws.com:6379"
      db_name                        = "app"
      stream_shard_count             = "1"
      ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
      api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api"
      worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker"
      import_extract_role_arn        = "arn:aws:iam::111111111111:role/example-dev-import-extract"
      import_load_role_arn           = "arn:aws:iam::111111111111:role/example-dev-import-load"
      agent_runtime_role_arn         = "arn:aws:iam::111111111111:role/example-dev-agent"
    }
    lists = {
      services          = ["api", "worker"]
      public_subnet_ids = ["subnet-0aaaaaaa00000001", "subnet-0aaaaaaa00000002"]
      app_subnet_ids    = ["subnet-0bbbbbbb00000001", "subnet-0bbbbbbb00000002"]
      agent_subnet_ids  = ["subnet-0ccccccc00000001", "subnet-0ccccccc00000002"]
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
