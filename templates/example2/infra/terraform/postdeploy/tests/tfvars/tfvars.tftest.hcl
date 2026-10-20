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
      alb_arn_suffix            = "app/example-dev-alb/0123456789abcdef"
      target_group_arn_suffixes = "{\"api\":\"targetgroup/example-dev-alb-api/0123456789ab\"}"
      cluster_name              = "example-dev-app"
      api_service_name          = "example-dev-api"
      worker_service_name       = "example-dev-worker"
      api_log_group_name        = "/ecs/example-dev-api"
      worker_log_group_name     = "/ecs/example-dev-worker"
      api_max_capacity          = "10"
      worker_max_capacity       = "6"
      stream_maxlen             = "100000"
      agent_runtime_arns        = "{\"agent\":\"arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:runtime/example_dev_agent-AbCdEfGh\"}"
      agent_memory_arn          = "arn:aws:bedrock-agentcore:ap-northeast-1:111111111111:memory/example_dev_memory-KlMnOpQr"
    }
  }
}

override_module {
  target = module.shared
  outputs = {
    strings = {
      alarm_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:example-dev-alarms"
    }
  }
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

run "tfvars_switch_every_feature_on" {
  command = plan

  assert {
    condition     = var.service_alarms_enabled && var.stream_alarms_enabled && var.log_alarms_enabled && var.tracing_enabled
    error_message = "The placeholder tfvars show every feature on; the defaults are off"
  }

  assert {
    condition     = length(module.service_alarms) == 2 && length(module.traces) == 1
    error_message = "With every feature on the modules exist"
  }
}
