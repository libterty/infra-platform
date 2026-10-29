# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

run "tfvars_build_the_foundation" {
  command = plan

  assert {
    condition     = module.kms.alias_name == "alias/${var.project}-${var.env}-governance"
    error_message = "The governance key must be created with the project and env alias"
  }

  assert {
    condition = (
      local.log_buckets.trail.name == "${var.project}-${var.env}-trail-${var.expected_account_id}" &&
      local.log_buckets.config.name == "${var.project}-${var.env}-config-${var.expected_account_id}"
    )
    error_message = "The log buckets must be named after the project, env and account"
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

run "tfvars_subscribe_someone_to_alerts" {
  command = plan

  assert {
    condition     = length(var.alert_emails) > 0
    error_message = "An alert topic without a subscriber is not an alert; give at least one email in tfvars"
  }
}
