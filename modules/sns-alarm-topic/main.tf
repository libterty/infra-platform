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

data "aws_caller_identity" "current" {
  count = length(var.service_publishers) == 0 ? 0 : 1
}

# Setting a topic policy replaces the SNS default, so the default owner statement is kept verbatim: same-account
# CloudWatch alarms publish through it (they set AWS:SourceOwner, not aws:SourceAccount).
resource "aws_sns_topic_policy" "this" {
  count = length(var.service_publishers) == 0 ? 0 : 1

  arn = aws_sns_topic.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OwnerAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "SNS:AddPermission",
          "SNS:DeleteTopic",
          "SNS:GetTopicAttributes",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:RemovePermission",
          "SNS:SetTopicAttributes",
          "SNS:Subscribe",
        ]
        Resource  = aws_sns_topic.this.arn
        Condition = { StringEquals = { "AWS:SourceOwner" = data.aws_caller_identity.current[0].account_id } }
      },
      {
        Sid       = "AllowServicePublish"
        Effect    = "Allow"
        Principal = { Service = sort(distinct(var.service_publishers)) }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.this.arn
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current[0].account_id } }
      },
    ]
  })
}
