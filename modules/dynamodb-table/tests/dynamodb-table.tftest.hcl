mock_provider "aws" {}

override_resource {
  target          = aws_dynamodb_table.this
  override_during = plan
  values = {
    arn        = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/alpha-dev-orders"
    stream_arn = "arn:aws:dynamodb:ap-northeast-1:111111111111:table/alpha-dev-orders/stream/2026-10-24T00:00:00.000"
  }
}

variables {
  name        = "alpha-dev-orders"
  kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  hash_key    = "id"
  attributes  = { id = "S" }
}

# ---- positive: billing -----------------------------------------------------------------------------------------

run "pay_per_request_is_the_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "billing_mode must default to PAY_PER_REQUEST"
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "id" && aws_dynamodb_table.this.range_key == null
    error_message = "hash_key must be passed through and range_key must be unset"
  }

  assert {
    condition     = toset([for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"]) == toset(["id:S"])
    error_message = "Exactly the key attribute must be declared"
  }

  assert {
    condition     = aws_dynamodb_table.this.table_class == "STANDARD"
    error_message = "table_class must default to STANDARD"
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 0
    error_message = "No GSI by default"
  }

  assert {
    condition     = length(aws_dynamodb_table.this.ttl) == 0
    error_message = "No TTL by default"
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == false
    error_message = "No stream by default"
  }
}

run "provisioned_with_capacity" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 2
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PROVISIONED"
    error_message = "billing_mode must be passed through"
  }

  assert {
    condition     = aws_dynamodb_table.this.read_capacity == 5 && aws_dynamodb_table.this.write_capacity == 2
    error_message = "Capacities must be passed through"
  }
}

run "range_key_declares_a_second_attribute" {
  command = plan

  variables {
    range_key  = "created_at"
    attributes = { id = "S", created_at = "N" }
  }

  assert {
    condition     = aws_dynamodb_table.this.range_key == "created_at"
    error_message = "range_key must be passed through"
  }

  assert {
    condition     = toset([for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"]) == toset(["id:S", "created_at:N"])
    error_message = "Both key attributes must be declared with their types"
  }
}

# ---- positive: GSI ---------------------------------------------------------------------------------------------

run "gsi_uses_key_schema_not_deprecated_keys" {
  command = plan

  variables {
    attributes = { id = "S", email = "S", created_at = "N" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", range_key = "created_at" }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 1
    error_message = "One GSI must be created"
  }

  assert {
    condition = toset([
      for k in one(aws_dynamodb_table.this.global_secondary_index).key_schema : "${k.key_type}:${k.attribute_name}"
    ]) == toset(["HASH:email", "RANGE:created_at"])
    error_message = "The GSI keys must be written as key_schema blocks"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).name == "by-email"
    error_message = "The map key must be the index name"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).projection_type == "ALL"
    error_message = "projection_type must default to ALL"
  }
}

run "gsi_hash_only_has_a_single_key_schema" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email" }
    }
  }

  assert {
    condition     = length(one(aws_dynamodb_table.this.global_secondary_index).key_schema) == 1
    error_message = "A hash-only GSI has one key_schema block"
  }
}

run "gsi_may_reuse_the_table_key_attributes" {
  command = plan

  variables {
    range_key  = "created_at"
    attributes = { id = "S", created_at = "N" }
    global_secondary_indexes = {
      by-created = { hash_key = "created_at", range_key = "id" }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.this.attribute) == 2
    error_message = "Attributes shared between the table and a GSI are declared once"
  }
}

run "gsi_include_projection" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", projection_type = "INCLUDE", non_key_attributes = ["status", "total"] }
    }
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).projection_type == "INCLUDE"
    error_message = "projection_type must be passed through"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).non_key_attributes == toset(["status", "total"])
    error_message = "non_key_attributes must be passed through"
  }
}

run "gsi_provisioned_capacity" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 5
    attributes     = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", read_capacity = 3, write_capacity = 1 }
    }
  }

  assert {
    condition     = one(aws_dynamodb_table.this.global_secondary_index).read_capacity == 3 && one(aws_dynamodb_table.this.global_secondary_index).write_capacity == 1
    error_message = "GSI capacities must be passed through"
  }
}

# ---- positive: ttl, stream, pitr, protection, encryption, insights ---------------------------------------------

run "ttl_attribute_enables_ttl" {
  command = plan

  variables {
    ttl_attribute = "expires_at"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).attribute_name == "expires_at" && one(aws_dynamodb_table.this.ttl).enabled == true
    error_message = "TTL must be enabled on the given attribute"
  }

  assert {
    condition     = length(aws_dynamodb_table.this.attribute) == 1
    error_message = "The TTL attribute is not a key and must not be declared as an attribute"
  }
}

run "stream_enabled_with_view_type" {
  command = plan

  variables {
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == true && aws_dynamodb_table.this.stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "A view type must enable the stream with that view type"
  }

  assert {
    condition     = output.stream_arn == "arn:aws:dynamodb:ap-northeast-1:111111111111:table/alpha-dev-orders/stream/2026-10-24T00:00:00.000"
    error_message = "stream_arn must be the table stream ARN when the stream is on"
  }
}

run "stream_arn_is_null_without_a_stream" {
  command = plan

  assert {
    condition     = output.stream_arn == null
    error_message = "stream_arn must be null when there is no stream"
  }
}

run "pitr_is_on_for_35_days_by_default" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled == true
    error_message = "PITR must be enabled"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).recovery_period_in_days == 35
    error_message = "PITR must default to 35 days"
  }
}

run "pitr_days_are_configurable" {
  command = plan

  variables {
    point_in_time_recovery_days = 7
  }

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled == true && one(aws_dynamodb_table.this.point_in_time_recovery).recovery_period_in_days == 7
    error_message = "A shorter window must keep PITR enabled"
  }
}

run "pitr_boundaries_are_accepted" {
  command = plan

  variables {
    point_in_time_recovery_days = 1
  }

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).recovery_period_in_days == 1
    error_message = "1 day is the minimum and must be accepted"
  }
}

run "deletion_protection_is_on_by_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true
    error_message = "deletion_protection must default to true"
  }
}

run "deletion_protection_can_be_turned_off_explicitly" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "An explicit false must be honoured"
  }
}

run "sse_uses_the_given_kms_key" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).enabled == true
    error_message = "SSE must be enabled"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).kms_key_arn == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "SSE must use the key given as input"
  }
}

run "contributor_insights_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 0
    error_message = "No contributor insights by default"
  }
}

run "contributor_insights_when_enabled" {
  command = plan

  variables {
    contributor_insights = true
  }

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 1
    error_message = "contributor_insights = true must create the resource"
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this[0].table_name == "alpha-dev-orders"
    error_message = "Contributor insights must point at the table"
  }
}

run "infrequent_access_table_class" {
  command = plan

  variables {
    table_class = "STANDARD_INFREQUENT_ACCESS"
  }

  assert {
    condition     = aws_dynamodb_table.this.table_class == "STANDARD_INFREQUENT_ACCESS"
    error_message = "table_class must be passed through"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Project"] == "alpha" && aws_dynamodb_table.this.tags["Name"] == "alpha-dev-orders"
    error_message = "Name must be added to the given tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.table_name == "alpha-dev-orders"
    error_message = "table_name must be the table name"
  }

  assert {
    condition     = output.arn == "arn:aws:dynamodb:ap-northeast-1:111111111111:table/alpha-dev-orders"
    error_message = "arn must be the table ARN"
  }
}

# ---- negative: attributes --------------------------------------------------------------------------------------

run "attributes_missing_the_hash_key_rejected" {
  command = plan

  variables {
    attributes = {}
  }

  expect_failures = [var.attributes]
}

run "attributes_missing_the_range_key_rejected" {
  command = plan

  variables {
    range_key = "created_at"
  }

  expect_failures = [var.attributes]
}

run "attributes_missing_a_gsi_key_rejected" {
  command = plan

  variables {
    global_secondary_indexes = {
      by-email = { hash_key = "email" }
    }
  }

  expect_failures = [var.attributes]
}

run "attributes_with_an_unused_attribute_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
  }

  expect_failures = [var.attributes]
}

run "attributes_with_the_ttl_attribute_rejected" {
  command = plan

  variables {
    ttl_attribute = "expires_at"
    attributes    = { id = "S", expires_at = "N" }
  }

  expect_failures = [var.attributes]
}

run "attribute_type_must_be_s_n_or_b" {
  command = plan

  variables {
    attributes = { id = "X" }
  }

  expect_failures = [var.attributes]
}

# ---- negative: billing mode and capacity -----------------------------------------------------------------------

run "unknown_billing_mode_rejected" {
  command = plan

  variables {
    billing_mode = "ON_DEMAND"
  }

  expect_failures = [var.billing_mode]
}

run "provisioned_without_capacity_rejected" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
  }

  expect_failures = [var.read_capacity, var.write_capacity]
}

run "provisioned_without_write_capacity_rejected" {
  command = plan

  variables {
    billing_mode  = "PROVISIONED"
    read_capacity = 5
  }

  expect_failures = [var.write_capacity]
}

run "provisioned_with_zero_capacity_rejected" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 0
    write_capacity = 0
  }

  expect_failures = [var.read_capacity, var.write_capacity]
}

run "pay_per_request_with_read_capacity_rejected" {
  command = plan

  variables {
    read_capacity = 5
  }

  expect_failures = [var.read_capacity]
}

run "pay_per_request_with_write_capacity_rejected" {
  command = plan

  variables {
    write_capacity = 5
  }

  expect_failures = [var.write_capacity]
}

run "provisioned_gsi_without_capacity_rejected" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 5
    attributes     = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email" }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "pay_per_request_gsi_with_capacity_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", read_capacity = 1, write_capacity = 1 }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

# ---- negative: GSI shape ---------------------------------------------------------------------------------------

run "gsi_unknown_projection_type_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", projection_type = "SOME" }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "gsi_include_without_non_key_attributes_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", projection_type = "INCLUDE" }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "gsi_non_key_attributes_without_include_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      by-email = { hash_key = "email", non_key_attributes = ["status"] }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "gsi_name_too_short_rejected" {
  command = plan

  variables {
    attributes = { id = "S", email = "S" }
    global_secondary_indexes = {
      ab = { hash_key = "email" }
    }
  }

  expect_failures = [var.global_secondary_indexes]
}

# ---- negative: stream, pitr, class, key, name ------------------------------------------------------------------

run "unknown_stream_view_type_rejected" {
  command = plan

  variables {
    stream_view_type = "ALL_IMAGES"
  }

  expect_failures = [var.stream_view_type]
}

run "pitr_zero_days_rejected" {
  command = plan

  variables {
    point_in_time_recovery_days = 0
  }

  expect_failures = [var.point_in_time_recovery_days]
}

run "pitr_36_days_rejected" {
  command = plan

  variables {
    point_in_time_recovery_days = 36
  }

  expect_failures = [var.point_in_time_recovery_days]
}

run "unknown_table_class_rejected" {
  command = plan

  variables {
    table_class = "GLACIER"
  }

  expect_failures = [var.table_class]
}

run "empty_ttl_attribute_rejected" {
  command = plan

  variables {
    ttl_attribute = ""
  }

  expect_failures = [var.ttl_attribute]
}

run "kms_alias_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:alias/alpha-dev"
  }

  expect_failures = [var.kms_key_arn]
}

run "kms_key_arn_is_required" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

run "name_too_short_rejected" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "name_with_a_slash_rejected" {
  command = plan

  variables {
    name = "alpha/dev"
  }

  expect_failures = [var.name]
}
