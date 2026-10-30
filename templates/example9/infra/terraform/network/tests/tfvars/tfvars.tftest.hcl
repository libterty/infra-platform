# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
mock_provider "aws" {}

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

run "tfvars_give_two_azs_in_the_region" {
  command = plan

  assert {
    condition     = length(var.azs) == 2 && alltrue([for az in var.azs : startswith(az, var.aws_region)])
    error_message = "The tfvars must list two AZs of the stack's region"
  }
}
