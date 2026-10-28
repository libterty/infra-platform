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

run "tfvars_zone_is_the_env_subdomain" {
  command = plan

  assert {
    condition     = var.domain_name == "${var.env}.example.com" && module.zone.name == var.domain_name
    error_message = "Each env gets its own subdomain zone <env>.example.com (design D4)"
  }
}
