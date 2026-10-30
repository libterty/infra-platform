locals {
  alert_topic = {
    name                = "${local.name_prefix}-alerts"
    email_subscriptions = var.alarm_emails
    kms_master_key_id   = module.kms.key_arn
    # The pipeline stack's EventBridge rule sends pipeline failures here (design K7).
    service_publishers = ["events.amazonaws.com"]
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
