mock_provider "aws" {}

variables {
  project                  = "baseline"
  env                      = "dev"
  expected_account_id      = "111111111111"
  vault_min_retention_days = 1
  backup_delete_after_days = 7
}

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

run "reads_only_the_keys_it_needs" {
  command = plan

  assert {
    condition = local.ssm_input_strings == {
      kms_key_arn     = "foundation/kms_key_arn"
      alert_topic_arn = "foundation/alert_topic_arn"
      backup_role_arn = "iam/backup_role_arn"
    } && local.ssm_input_lists == {}
    error_message = "backup may read only the governance key, the alert topic and the Backup role (design 8.2)"
  }
}

run "vault_uses_the_governance_key_and_denies_deletion" {
  command = plan

  assert {
    condition     = local.vault.name == "baseline-dev-backup" && module.vault.name == "baseline-dev-backup"
    error_message = "The vault must be named <name_prefix>-backup"
  }

  assert {
    condition     = local.vault.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "Recovery points must be encrypted with the governance key from foundation"
  }

  assert {
    condition     = local.vault.deny_delete_recovery_points == true && local.vault.force_destroy == false
    error_message = "The vault policy must deny deleting recovery points, and destroy must not empty the vault (design section 4)"
  }
}

run "vault_lock_is_governance_mode_only" {
  command = plan

  assert {
    condition     = local.vault.lock.min_retention_days == 1 && local.vault.lock.max_retention_days == 365
    error_message = "The dev lock keeps recovery points between 1 and 365 days (design 8.3)"
  }

  assert {
    condition     = toset(keys(local.vault.lock)) == toset(["min_retention_days", "max_retention_days"])
    error_message = "The lock must stay in governance mode: compliance mode can never be undone (design K11)"
  }

  assert {
    condition     = length(regexall("changeable_for_days|compliance_acknowledged", file("${path.module}/backup.tf"))) == 0
    error_message = "backup.tf must not set changeable_for_days or compliance_acknowledged"
  }
}

run "vault_notifies_failures_to_the_alert_topic" {
  command = plan

  assert {
    condition     = local.vault.notifications.sns_topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:baseline-dev-alerts"
    error_message = "Vault events must go to the alert topic from foundation"
  }

  assert {
    condition     = toset(local.vault.notifications.events) == toset(["BACKUP_JOB_FAILED", "BACKUP_JOB_EXPIRED", "RESTORE_JOB_FAILED"])
    error_message = "Only failed or missed backup jobs and failed restores are alerts"
  }
}

run "daily_plan_selects_by_the_backup_tag" {
  command = plan

  assert {
    condition     = local.plan.selection_tags == { backup = "daily" }
    error_message = "Resources are selected by the tag backup = daily and nothing else (design K10)"
  }

  assert {
    condition     = local.plan.name == "baseline-dev-daily" && module.vault.name == local.plan.vault_name
    error_message = "The plan must be named <name_prefix>-daily and store into the vault of this stack"
  }

  assert {
    condition     = local.plan.role_arn == "arn:aws:iam::111111111111:role/baseline-dev-backup"
    error_message = "The plan must run as the Backup role from the iam stack (design K4)"
  }

  assert {
    condition = local.plan.rules == {
      daily = { schedule = "cron(0 19 * * ? *)", delete_after_days = 7 }
    }
    error_message = "One daily rule at 03:00 UTC+8 (19:00 UTC), kept 7 days in dev (design 8.3)"
  }
}

run "publishes_exactly_the_vault_name" {
  command = plan

  assert {
    condition     = module.ssm_publish.names == { vault_name = "/baseline/dev/backup/vault_name" }
    error_message = "ssm-publish must write only vault_name under the backup stack path (design 8.2)"
  }
}

run "retention_below_the_lock_minimum_rejected" {
  command = plan

  variables {
    vault_min_retention_days = 7
    backup_delete_after_days = 5
  }

  expect_failures = [var.backup_delete_after_days]
}

run "retention_above_the_lock_maximum_rejected" {
  command = plan

  variables {
    backup_delete_after_days = 366
  }

  expect_failures = [var.backup_delete_after_days]
}

run "lock_minimum_below_one_rejected" {
  command = plan

  variables {
    vault_min_retention_days = 0
  }

  expect_failures = [var.vault_min_retention_days]
}

run "sit_retention_passes" {
  command = plan

  variables {
    env                      = "sit"
    expected_account_id      = "222222222222"
    vault_min_retention_days = 7
    backup_delete_after_days = 35
  }

  assert {
    condition     = local.vault.lock.min_retention_days == 7 && local.plan.rules.daily.delete_after_days == 35
    error_message = "sit keeps backups 35 days with a 7-day lock minimum (design 8.3)"
  }
}

# ---- common.tf and providers.tf guards: the same runs in every stack ----

run "env_format_uppercase_rejected" {
  command = plan

  variables {
    env = "Dev"
  }

  expect_failures = [var.env]
}

run "env_format_too_short_rejected" {
  command = plan

  variables {
    env = "d"
  }

  expect_failures = [var.env]
}

run "env_format_valid_passes" {
  command = plan

  variables {
    env = "dev"
  }

  assert {
    condition     = local.name_prefix == "baseline-dev" && local.ssm_prefix == "/baseline/dev"
    error_message = "A valid env must give the name prefix and the SSM prefix"
  }
}

run "project_format_rejected" {
  command = plan

  variables {
    project = "Example"
  }

  expect_failures = [var.project]
}

run "account_must_match_env" {
  command = plan

  variables {
    env                 = "dev"
    expected_account_id = "222222222222"
  }

  expect_failures = [var.expected_account_id]
}

run "account_unknown_env_rejected" {
  command = plan

  variables {
    env                 = "staging"
    expected_account_id = "111111111111"
  }

  expect_failures = [var.expected_account_id]
}

run "account_matching_env_passes" {
  command = plan

  variables {
    env                 = "sit"
    expected_account_id = "222222222222"
  }

  assert {
    condition     = local.name_prefix == "baseline-sit" && contains(local.accounts_by_env["sit"], var.expected_account_id)
    error_message = "A sit account with env sit must pass"
  }
}

run "account_is_required" {
  command = plan

  variables {
    expected_account_id = null
  }

  expect_failures = [var.expected_account_id]
}

# A default would let a missing tfvars file point at some account silently.
run "account_has_no_default" {
  command = plan

  assert {
    condition     = length(regexall("(?s)variable \"expected_account_id\" \\{[^}]*\\n\\s*default\\s*=", file("${path.module}/common.tf"))) == 0
    error_message = "expected_account_id must not have a default value"
  }
}

run "deploy_role_in_other_account_rejected" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::222222222222:role/deploy"
  }

  expect_failures = [var.deploy_role_arn]
}

run "deploy_role_in_expected_account_passes" {
  command = plan

  variables {
    deploy_role_arn = "arn:aws:iam::111111111111:role/deploy"
  }

  assert {
    condition     = var.deploy_role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "A role in the expected account must pass"
  }
}
