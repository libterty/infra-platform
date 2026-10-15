locals {
  alarm_topic = {
    name                = "${local.name_prefix}-alarms"
    email_subscriptions = var.alarm_emails
    kms_master_key_id   = module.kms.key_arn
  }
}

module "alarm_topic" {
  source = "../../../../../modules/sns-alarm-topic"

  name                = local.alarm_topic.name
  email_subscriptions = local.alarm_topic.email_subscriptions
  kms_master_key_id   = local.alarm_topic.kms_master_key_id
}
