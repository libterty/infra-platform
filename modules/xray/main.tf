resource "aws_xray_sampling_rule" "this" {
  for_each = var.sampling_rules

  rule_name      = "${var.name_prefix}-${each.key}"
  priority       = each.value.priority
  fixed_rate     = each.value.fixed_rate
  reservoir_size = each.value.reservoir_size
  service_name   = each.value.service_name
  service_type   = each.value.service_type
  host           = each.value.host
  http_method    = each.value.http_method
  url_path       = each.value.url_path
  attributes     = each.value.attributes

  # Required by the provider; resource_arn is not exposed because it only
  # matters for sampling by resource and * matches everything.
  version      = 1
  resource_arn = "*"

  tags = var.tags
}

resource "aws_xray_group" "this" {
  for_each = var.groups

  group_name        = "${var.name_prefix}-${each.key}"
  filter_expression = each.value.filter_expression

  insights_configuration {
    insights_enabled      = each.value.insights_enabled
    notifications_enabled = each.value.notifications_enabled
  }

  tags = var.tags
}
