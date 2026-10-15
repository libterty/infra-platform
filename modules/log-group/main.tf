resource "aws_cloudwatch_log_group" "this" {
  name              = var.name
  retention_in_days = var.retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_cloudwatch_log_subscription_filter" "this" {
  count = var.subscription == null ? 0 : 1

  name            = var.name
  log_group_name  = aws_cloudwatch_log_group.this.name
  filter_pattern  = var.subscription.filter_pattern
  destination_arn = var.subscription.destination_arn
  role_arn        = var.subscription.role_arn
}
