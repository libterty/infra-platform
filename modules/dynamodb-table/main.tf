locals {
  # Every attribute that serves as a key of the table or of a GSI. DynamoDB requires the attribute definitions to be
  # exactly this set: a missing one fails the request, and an extra one is rejected as unused.
  key_attribute_names = distinct(concat(
    [var.hash_key],
    var.range_key == null ? [] : [var.range_key],
    flatten([
      for g in values(var.global_secondary_indexes) :
      concat([g.hash_key], g.range_key == null ? [] : [g.range_key])
    ]),
  ))
}

resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = var.billing_mode
  table_class  = var.table_class

  hash_key  = var.hash_key
  range_key = var.range_key

  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity

  deletion_protection_enabled = var.deletion_protection

  stream_enabled   = var.stream_view_type != null
  stream_view_type = var.stream_view_type

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.key
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      read_capacity      = global_secondary_index.value.read_capacity
      write_capacity     = global_secondary_index.value.write_capacity

      # hash_key and range_key are deprecated in the provider; key_schema replaces them.
      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }

      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key == null ? [] : [global_secondary_index.value.range_key]
        content {
          attribute_name = key_schema.value
          key_type       = "RANGE"
        }
      }
    }
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute == null ? [] : [var.ttl_attribute]
    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  # Recovery and encryption are not optional: PITR is always on and the table always uses the given key.
  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = var.point_in_time_recovery_days
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_dynamodb_contributor_insights" "this" {
  count = var.contributor_insights ? 1 : 0

  table_name = aws_dynamodb_table.this.name
}
