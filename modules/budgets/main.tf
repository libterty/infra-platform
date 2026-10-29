resource "aws_budgets_budget" "this" {
  for_each = var.budgets

  name         = each.key
  budget_type  = "COST"
  limit_amount = tostring(each.value.limit_amount)
  limit_unit   = "USD"
  time_unit    = each.value.time_unit

  dynamic "cost_filter" {
    for_each = each.value.cost_filters
    content {
      name   = cost_filter.key
      values = cost_filter.value
    }
  }

  dynamic "notification" {
    for_each = each.value.notifications
    content {
      comparison_operator        = notification.value.comparison
      threshold                  = notification.value.threshold
      threshold_type             = notification.value.threshold_type
      notification_type          = notification.value.type
      subscriber_sns_topic_arns  = notification.value.sns_topic_arns
      subscriber_email_addresses = notification.value.emails
    }
  }

  tags = merge(var.tags, { Name = each.key })
}
