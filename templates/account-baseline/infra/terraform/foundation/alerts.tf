locals {
  alert_topic = {
    name                = "${local.name_prefix}-alerts"
    email_subscriptions = var.alert_emails
    kms_master_key_id   = module.kms.key_arn
    # Budgets (budget stack), Backup (backup stack) and EventBridge rules for findings (detect stack).
    service_publishers = ["budgets.amazonaws.com", "backup.amazonaws.com", "events.amazonaws.com"]
  }
}

module "alert_topic" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sns-alarm-topic/aws"
  version = "~> 0.2.0"

  name                = local.alert_topic.name
  email_subscriptions = local.alert_topic.email_subscriptions
  kms_master_key_id   = local.alert_topic.kms_master_key_id
  service_publishers  = local.alert_topic.service_publishers
}
