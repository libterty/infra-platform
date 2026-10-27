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

# Design section 7.5 and D4: the CA is off in dev and sit; envs/examples/pki.tfvars shows how to turn it on.
run "tfvars_leave_the_ca_off" {
  command = plan

  assert {
    condition     = var.ca == null && length(module.ca) == 0
    error_message = "dev and sit tfvars must not create a CA"
  }

  assert {
    condition     = local.published_strings == { ca = "{\"enabled\":false}" }
    error_message = "With the CA off, pki must publish {\"enabled\":false}"
  }
}
