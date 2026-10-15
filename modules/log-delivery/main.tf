resource "aws_cloudwatch_log_delivery_source" "this" {
  for_each = var.sources

  name         = "${var.name_prefix}-${each.key}"
  resource_arn = each.value.resource_arn
  log_type     = each.value.log_type

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  for_each = var.destinations

  name                      = "${var.name_prefix}-${each.key}"
  delivery_destination_type = each.value.type == "XRAY" ? "XRAY" : null

  dynamic "delivery_destination_configuration" {
    for_each = each.value.type == "XRAY" ? [] : [each.value.resource_arn]
    content {
      destination_resource_arn = delivery_destination_configuration.value
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

# The replacement trigger below may only index by each.key, so the source ARN of each delivery is mirrored here under the delivery key.
resource "terraform_data" "source_arn" {
  for_each = var.deliveries

  input = aws_cloudwatch_log_delivery_source.this[each.value.source].resource_arn
}

resource "aws_cloudwatch_log_delivery" "this" {
  for_each = var.deliveries

  delivery_source_name     = aws_cloudwatch_log_delivery_source.this[each.value.source].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this[each.value.destination].arn

  tags = var.tags

  lifecycle {
    # When the emitting resource is recreated its source is replaced; deleting a source that still has a
    # delivery fails with ConflictException, so the delivery must be replaced with it. Tag-only changes do not trigger this.
    replace_triggered_by = [terraform_data.source_arn[each.key].output]
  }
}
