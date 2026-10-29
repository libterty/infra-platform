# Run by scripts/validate.sh with -var-file=envs/<env>.tfvars; it checks the tfvars files themselves.
# The upstream values below stand in for what the earlier stacks publish.
mock_provider "aws" {}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/kms_key_arn"]
  values = { insecure_value = "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["foundation/alert_topic_arn"]
  values = { insecure_value = "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts" }
}

override_data {
  target = module.in.data.aws_ssm_parameter.this["iam/backup_role_arn"]
  values = { insecure_value = "arn:aws:iam::111111111111:role/baseline-dev-backup" }
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

run "tfvars_retention_follows_the_env" {
  command = plan

  assert {
    condition = (
      var.env == "dev"
      ? var.vault_min_retention_days == 1 && var.backup_delete_after_days == 7
      : var.vault_min_retention_days == 7 && var.backup_delete_after_days == 35
    )
    error_message = "dev keeps backups 7 days with a 1-day lock minimum, sit 35 days with 7 (design 8.3)"
  }

  assert {
    condition     = local.vault.name == "${var.project}-${var.env}-backup" && local.plan.name == "${var.project}-${var.env}-daily"
    error_message = "The vault and plan names must be built from the tfvars project and env"
  }
}
