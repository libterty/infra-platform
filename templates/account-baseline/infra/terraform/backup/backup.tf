# Vault for the daily backups of this account. The lock stays in governance mode (design K11): compliance mode can
# never be removed, not even by AWS, so it is a decision for whoever copies the template.
locals {
  vault = {
    name                        = "${local.name_prefix}-backup"
    kms_key_arn                 = module.in.strings["kms_key_arn"]
    force_destroy               = false
    deny_delete_recovery_points = true
    lock = {
      min_retention_days = var.vault_min_retention_days
      max_retention_days = 365
    }
    notifications = {
      sns_topic_arn = module.in.strings["alert_topic_arn"]
      # Failures only; BACKUP_JOB_EXPIRED is a job that never started in its window, i.e. a missed backup.
      events = ["BACKUP_JOB_FAILED", "BACKUP_JOB_EXPIRED", "RESTORE_JOB_FAILED"]
    }
  }

  plan = {
    name       = "${local.name_prefix}-daily"
    vault_name = module.vault.name
    role_arn   = module.in.strings["backup_role_arn"]
    rules = {
      # 03:00 UTC+8; Backup schedules are in UTC.
      daily = { schedule = "cron(0 19 * * ? *)", delete_after_days = var.backup_delete_after_days }
    }
    # Application templates opt in by tagging their resources (design K10).
    selection_tags = { backup = "daily" }
  }
}

module "vault" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/backup-vault/aws"
  version = "~> 0.1.0"

  name                        = local.vault.name
  kms_key_arn                 = local.vault.kms_key_arn
  force_destroy               = local.vault.force_destroy
  deny_delete_recovery_points = local.vault.deny_delete_recovery_points
  lock                        = local.vault.lock
  notifications               = local.vault.notifications
}

module "plan" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/backup-plan/aws"
  version = "~> 0.1.0"

  name           = local.plan.name
  vault_name     = local.plan.vault_name
  role_arn       = local.plan.role_arn
  rules          = local.plan.rules
  selection_tags = local.plan.selection_tags
}
