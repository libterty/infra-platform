mock_provider "aws" {}

override_resource {
  target          = aws_backup_vault.this
  override_during = plan
  values = {
    arn = "arn:aws:backup:ap-northeast-1:111111111111:backup-vault:alpha-dev-backup"
  }
}

variables {
  name        = "alpha-dev-backup"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# ---- positive -------------------------------------------------------------------------------------------------

run "defaults_deny_recovery_point_deletion" {
  command = plan

  assert {
    condition     = aws_backup_vault.this.name == "alpha-dev-backup" && aws_backup_vault.this.kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The vault must keep the given name and use the given CMK"
  }

  assert {
    condition     = aws_backup_vault.this.force_destroy == false
    error_message = "force_destroy must default to false"
  }

  assert {
    condition     = length(aws_backup_vault_policy.this) == 1 && aws_backup_vault_policy.this[0].backup_vault_name == "alpha-dev-backup"
    error_message = "The deny-delete vault policy must be created by default"
  }

  assert {
    condition = jsondecode(aws_backup_vault_policy.this[0].policy).Statement == [{
      Sid       = "DenyRecoveryPointDeletion"
      Effect    = "Deny"
      Principal = { AWS = "*" }
      Action = [
        "backup:DeleteRecoveryPoint",
        "backup:UpdateRecoveryPointLifecycle",
        "backup:PutBackupVaultAccessPolicy",
      ]
      Resource = "*"
    }]
    error_message = "The vault policy must deny deleting recovery points, changing their lifecycle and replacing the policy for every principal"
  }

  assert {
    condition     = length(aws_backup_vault_lock_configuration.this) == 0 && length(aws_backup_vault_notifications.this) == 0
    error_message = "No lock and no notifications without lock and notifications"
  }

  assert {
    condition     = aws_backup_vault.this.tags["Name"] == "alpha-dev-backup"
    error_message = "The vault must carry a Name tag"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.arn == aws_backup_vault.this.arn && output.name == "alpha-dev-backup"
    error_message = "arn and name must expose the vault"
  }
}

run "deny_policy_can_be_turned_off" {
  command = plan

  variables {
    deny_delete_recovery_points = false
  }

  assert {
    condition     = length(aws_backup_vault_policy.this) == 0
    error_message = "No vault policy when deny_delete_recovery_points is false"
  }
}

run "governance_lock" {
  command = plan

  variables {
    lock = {
      min_retention_days = 7
      max_retention_days = 35
    }
  }

  assert {
    condition     = length(aws_backup_vault_lock_configuration.this) == 1
    error_message = "A lock must create the lock configuration"
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this[0].min_retention_days == 7 && aws_backup_vault_lock_configuration.this[0].max_retention_days == 35
    error_message = "The retention bounds must be passed through"
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this[0].changeable_for_days == null
    error_message = "Without changeable_for_days the lock must stay in governance mode"
  }
}

run "compliance_lock_when_acknowledged" {
  command = plan

  variables {
    lock = {
      min_retention_days      = 7
      max_retention_days      = 35
      changeable_for_days     = 3
      compliance_acknowledged = true
    }
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this[0].changeable_for_days == 3
    error_message = "changeable_for_days must be passed through for compliance mode"
  }
}

run "notifications" {
  command = plan

  variables {
    notifications = {
      sns_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      events        = ["BACKUP_JOB_COMPLETED", "COPY_JOB_FAILED"]
    }
  }

  assert {
    condition     = aws_backup_vault_notifications.this[0].sns_topic_arn == "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
    error_message = "The SNS topic must be passed through"
  }

  assert {
    condition     = aws_backup_vault_notifications.this[0].backup_vault_events == toset(["BACKUP_JOB_COMPLETED", "COPY_JOB_FAILED"])
    error_message = "The events must be passed through"
  }
}

run "region_on_every_resource" {
  command = plan

  variables {
    region = "us-east-1"
    lock = {
      min_retention_days = 7
    }
    notifications = {
      sns_topic_arn = "arn:aws:sns:us-east-1:111111111111:alpha-dev-alarms"
      events        = ["BACKUP_JOB_COMPLETED"]
    }
  }

  assert {
    condition = (
      aws_backup_vault.this.region == "us-east-1" &&
      aws_backup_vault_policy.this[0].region == "us-east-1" &&
      aws_backup_vault_lock_configuration.this[0].region == "us-east-1" &&
      aws_backup_vault_notifications.this[0].region == "us-east-1"
    )
    error_message = "region must be set on every resource"
  }
}

# ---- negative -------------------------------------------------------------------------------------------------

run "compliance_without_acknowledgement_rejected" {
  command = plan

  variables {
    lock = {
      min_retention_days  = 7
      changeable_for_days = 3
    }
  }

  expect_failures = [var.lock]
}

run "changeable_for_days_below_3_rejected" {
  command = plan

  variables {
    lock = {
      min_retention_days      = 7
      changeable_for_days     = 2
      compliance_acknowledged = true
    }
  }

  expect_failures = [var.lock]
}

run "min_above_max_rejected" {
  command = plan

  variables {
    lock = {
      min_retention_days = 36
      max_retention_days = 35
    }
  }

  expect_failures = [var.lock]
}

run "lock_without_retention_rejected" {
  command = plan

  variables {
    lock = {}
  }

  expect_failures = [var.lock]
}

run "unknown_event_rejected" {
  command = plan

  variables {
    notifications = {
      sns_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      events        = ["BACKUP_JOB_EXPLODED"]
    }
  }

  expect_failures = [var.notifications]
}

run "empty_events_rejected" {
  command = plan

  variables {
    notifications = {
      sns_topic_arn = "arn:aws:sns:ap-northeast-1:111111111111:alpha-dev-alarms"
      events        = []
    }
  }

  expect_failures = [var.notifications]
}

run "topic_arn_format_rejected" {
  command = plan

  variables {
    notifications = {
      sns_topic_arn = "alpha-dev-alarms"
      events        = ["BACKUP_JOB_COMPLETED"]
    }
  }

  expect_failures = [var.notifications]
}

run "kms_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/backup"
  }

  expect_failures = [var.kms_key_arn]
}

run "name_format_rejected" {
  command = plan

  variables {
    name = "alpha dev backup"
  }

  expect_failures = [var.name]
}

run "region_format_rejected" {
  command = plan

  variables {
    region = "ap_northeast_1"
  }

  expect_failures = [var.region]
}
