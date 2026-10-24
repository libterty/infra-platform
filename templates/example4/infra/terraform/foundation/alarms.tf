locals {
  alarm_topic = {
    name                = "${local.name_prefix}-alarms"
    email_subscriptions = var.alarm_emails
    kms_master_key_id   = module.kms.key_arn
  }
}

module "alarm_topic" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sns-alarm-topic/aws"
  version = "~> 0.1.1"

  name                = local.alarm_topic.name
  email_subscriptions = local.alarm_topic.email_subscriptions
  kms_master_key_id   = local.alarm_topic.kms_master_key_id
}
