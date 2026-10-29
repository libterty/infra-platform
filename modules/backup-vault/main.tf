resource "aws_backup_vault" "this" {
  region        = var.region
  name          = var.name
  kms_key_arn   = var.kms_key_arn
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_backup_vault_policy" "this" {
  count = var.deny_delete_recovery_points ? 1 : 0

  region            = var.region
  backup_vault_name = aws_backup_vault.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyRecoveryPointDeletion"
      Effect    = "Deny"
      Principal = { AWS = "*" }
      # Also denies replacing this policy, so nobody can lift the deny with a single policy update.
      Action = [
        "backup:DeleteRecoveryPoint",
        "backup:UpdateRecoveryPointLifecycle",
        "backup:PutBackupVaultAccessPolicy",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_backup_vault_lock_configuration" "this" {
  count = var.lock == null ? 0 : 1

  region              = var.region
  backup_vault_name   = aws_backup_vault.this.name
  min_retention_days  = var.lock.min_retention_days
  max_retention_days  = var.lock.max_retention_days
  changeable_for_days = var.lock.changeable_for_days
}

resource "aws_backup_vault_notifications" "this" {
  count = var.notifications == null ? 0 : 1

  region              = var.region
  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = var.notifications.sns_topic_arn
  backup_vault_events = var.notifications.events
}
