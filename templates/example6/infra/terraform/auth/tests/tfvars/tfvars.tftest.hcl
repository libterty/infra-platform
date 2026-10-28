# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["dns/zone_name"]
  values = { insecure_value = "dev.example.com" }
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

# Design 8.1 and 8.3: only dev calls back to the local dev server; deletion protection is off in dev and on in sit.
run "tfvars_follow_the_env_defaults" {
  command = plan

  assert {
    condition     = var.local_dev_origins == (var.env == "dev" ? ["http://localhost:5173"] : [])
    error_message = "Only dev may list the local dev server http://localhost:5173"
  }

  assert {
    condition     = var.deletion_protection == (var.env != "dev")
    error_message = "Deletion protection must be off in dev and on in sit"
  }

  assert {
    condition     = var.domain_prefix == "${var.project}-${var.env}-login"
    error_message = "The domain prefix must follow <project>-<env>-login"
  }
}
