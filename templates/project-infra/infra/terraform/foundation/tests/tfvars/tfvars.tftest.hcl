# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }

  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::111122223333:root" }
  }
}

run "tfvars_build_the_foundation" {
  command = plan

  assert {
    condition     = length(module.log_bucket) == 2
    error_message = "Both log buckets must be created whatever the tfvars say"
  }

  assert {
    condition     = module.kms.alias_name == "alias/${var.project}-${var.env}"
    error_message = "The shared key must be created with the project and env alias"
  }

  assert {
    condition     = module.app_secret.name == "${var.project}-${var.env}/app"
    error_message = "The application secret container must be created"
  }
}

run "tfvars_subscribe_someone_to_alarms" {
  command = plan

  assert {
    condition     = length(var.alarm_emails) > 0
    error_message = "An alarm topic without a subscriber is not an alarm; give at least one email in tfvars"
  }
}
