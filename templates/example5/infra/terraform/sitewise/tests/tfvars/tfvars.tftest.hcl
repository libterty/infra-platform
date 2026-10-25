# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}
mock_provider "awscc" {}

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

# Design section 7.5: no cameras in dev and sit.
run "tfvars_create_nothing" {
  command = plan

  assert {
    condition     = length(var.cameras) == 0 && length(var.gateways) == 0 && length(module.sitewise) == 0
    error_message = "dev and sit tfvars must not create SiteWise resources"
  }
}
