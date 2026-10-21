data "aws_caller_identity" "current" {}

locals {
  trusted_account_ids = setunion([data.aws_caller_identity.current.account_id], var.allowed_account_ids)

  # Also read by the sources and destinations validations in variables.tf and the source account check below.
  destination_arn_patterns = {
    CWL = "^arn:aws[a-z-]*:logs:[a-z0-9-]+:[0-9]{12}:log-group:[^:*]+(:[*])?$"
    S3  = "^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"
    FH  = "^arn:aws[a-z-]*:firehose:[a-z0-9-]+:[0-9]{12}:deliverystream/[A-Za-z0-9_.-]{1,64}$"
  }
}

resource "aws_cloudwatch_log_delivery_source" "this" {
  for_each = var.sources

  name         = "${var.name_prefix}-${each.key}"
  resource_arn = each.value.resource_arn
  log_type     = each.value.log_type

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })

  lifecycle {
    # Variable validation cannot read data sources, so the account check lives here. Only S3 bucket ARNs, which carry
    # no account, are skipped; the match is explicit so a looser validation regex cannot widen the exemption.
    precondition {
      condition     = can(regex(local.destination_arn_patterns.S3, each.value.resource_arn)) || contains(local.trusted_account_ids, split(":", each.value.resource_arn)[4])
      error_message = "Source ${each.key} is in account ${split(":", each.value.resource_arn)[4]}, which is neither the current account nor listed in allowed_account_ids."
    }
  }
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

  lifecycle {
    # CWL and FH are checked: S3 bucket ARNs carry no account and XRAY has no ARN.
    precondition {
      condition     = !contains(["CWL", "FH"], each.value.type) ? true : contains(local.trusted_account_ids, split(":", each.value.resource_arn)[4])
      error_message = "Destination ${each.key} is in account ${contains(["CWL", "FH"], each.value.type) ? split(":", each.value.resource_arn)[4] : ""}, which is neither the current account nor listed in allowed_account_ids."
    }
  }
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
