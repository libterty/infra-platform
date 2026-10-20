# The account and env checks in common.tf and providers.tf. Every stack carries the same file.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  project             = "example"
  env                 = "dev"
  expected_account_id = "111111111111"
  # Required variables of this stack, so the account checks can plan.
  api_image_tag      = "0.1.0"
  worker_image_tag   = "0.1.0"
  cors_allow_origins = ["https://app.example.com"]
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.in
  outputs = {
    strings = {
      api_target_group_arn = "arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab"
      alb_arn_suffix       = "app/example-dev-alb/0123456789abcdef"
      agent_runtime_arns   = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\"}"
      guardrail_ids        = "{\"default\":\"gr0input00001\",\"output\":\"gr0output00003\"}"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      vpc_id                         = "vpc-0123456789abcdef0"
      app_sg_id                      = "sg-0123456789abcdef0"
      ecs_execution_role_arn         = "arn:aws:iam::111111111111:role/example-dev-ecs-execution"
      api_task_role_arn              = "arn:aws:iam::111111111111:role/example-dev-api-task"
      worker_task_role_arn           = "arn:aws:iam::111111111111:role/example-dev-worker-task"
      signing_private_key_secret_arn = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-private-key-GhIjKl"
      signing_public_key_secret_arn  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:example-dev/app-signing-public-key-AbCdEf"
      db_proxy_endpoint              = "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn                  = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      rate_limit_redis_endpoint      = "clustercfg.example-dev-rate-limit.abc123.apne1.cache.amazonaws.com:6379"
      stream_redis_endpoint          = "clustercfg.example-dev-stream.abc123.apne1.cache.amazonaws.com:6379"
      db_name                        = "app"
      stream_shard_count             = "3"
      ecr_repository_urls = jsonencode({
        api    = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api"
        worker = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker"
      })
    }
    lists = {
      app_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
      services       = ["api", "worker", "import-extract", "import-load"]
    }
  }
}

override_data {
  target = data.aws_vpc.this
  values = { cidr_block = "10.10.0.0/16" }
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
