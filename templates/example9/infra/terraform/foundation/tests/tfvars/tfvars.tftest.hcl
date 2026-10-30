# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

run "tfvars_build_the_foundation" {
  command = plan

  assert {
    condition     = module.kms.alias_name == "alias/${var.project}-${var.env}"
    error_message = "The shared key must be created with the project and env alias"
  }

  assert {
    condition     = local.artifact_bucket.name == "${var.project}-${var.env}-artifacts-${var.expected_account_id}" && local.connection.name == "${var.project}-${var.env}-github"
    error_message = "The artifact bucket and the connection must be named after the project, env and account"
  }

  assert {
    condition     = length(local.connection.name) <= 32
    error_message = "The connection name must fit in 32 characters; shorten project"
  }
}

run "tfvars_env_and_account_correspond" {
  command = plan

  assert {
    condition     = contains(["dev", "sit"], var.env)
    error_message = "env must be dev or sit; these are the only environments"
  }

  assert {
    condition     = var.expected_account_id == (var.env == "dev" ? "111111111111" : "222222222222")
    error_message = "dev must point at the placeholder account 111111111111 and sit at 222222222222"
  }
}

run "tfvars_subscribe_someone_to_alarms" {
  command = plan

  assert {
    condition     = length(var.alarm_emails) > 0
    error_message = "An alarm topic without a subscriber is not an alarm; give at least one email in tfvars"
  }
}
