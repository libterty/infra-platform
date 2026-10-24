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
    condition     = local.flow_log_bucket.name == "${var.project}-${var.env}-flow-logs-${var.expected_account_id}"
    error_message = "The flow log bucket must be named after the project, env and account"
  }

  assert {
    condition     = aws_secretsmanager_secret.opensearch_master.name == "${var.project}-${var.env}/opensearch-master"
    error_message = "The OpenSearch master secret container must be created"
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

# Design D13: dev and sit both turn the account-level catalog encryption on.
run "tfvars_enable_glue_catalog_encryption" {
  command = plan

  assert {
    condition     = var.glue_catalog_encryption != null && length(module.glue_catalog_encryption) == 1
    error_message = "dev and sit tfvars must set glue_catalog_encryption (the second project in an account sets null)"
  }
}
