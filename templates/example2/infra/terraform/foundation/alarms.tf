locals {
  alarm_topic = {
    name                = "${local.name_prefix}-alarms"
    email_subscriptions = var.alarm_emails
  }
}

# The topic is not encrypted: CloudWatch alarms cannot publish to a topic that uses the AWS managed SNS key.
module "alarm_topic" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/sns-alarm-topic/aws"
  version = "~> 0.1.0"

  name                = local.alarm_topic.name
  email_subscriptions = local.alarm_topic.email_subscriptions
}
