# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
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
