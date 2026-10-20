# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

# The SSM values are only read here, so fixed ones stand in for them (the mock would return random text).
override_module {
  target = module.shared
  outputs = {
    strings = {
      agent_sg_id            = "sg-0123456789abcdef0"
      agent_runtime_role_arn = "arn:aws:iam::111111111111:role/example-dev-agent-runtime"
      agent_runtimes         = "[\"agent\"]"
      db_proxy_endpoint      = "example-dev-proxy.proxy-abc.ap-northeast-1.rds.amazonaws.com"
      db_secret_arn          = "arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000"
      db_name                = "app"
      ecr_repository_urls    = jsonencode({ agent = "111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-agent" })
    }
    lists = {
      agent_subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
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
