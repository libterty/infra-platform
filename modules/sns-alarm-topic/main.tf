resource "aws_sns_topic" "this" {
  name              = var.name
  kms_master_key_id = var.kms_master_key_id

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_subscriptions)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}
