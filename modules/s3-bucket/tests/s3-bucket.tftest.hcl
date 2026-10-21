mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-flow-logs"
    bucket                      = "alpha-dev-flow-logs"
    bucket_regional_domain_name = "alpha-dev-flow-logs.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name = "alpha-dev-flow-logs"
}

run "public_access_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be true"
  }
}

run "ownership_enforced" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced"
  }
}

run "tags_are_merged_with_name" {
  command = plan

  variables {
    tags = { Project = "alpha" }
  }

  assert {
    condition     = aws_s3_bucket.this.tags == tomap({ Project = "alpha", Name = "alpha-dev-flow-logs" })
    error_message = "Input tags must be kept and Name added"
  }
}

run "tls_only_deny_always" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1
    error_message = "With log_delivery empty the policy must have exactly one statement"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny"
    error_message = "The TLS statement must be a Deny"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The Deny must match aws:SecureTransport = false"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Resource) == jsonencode(["arn:aws:s3:::alpha-dev-flow-logs", "arn:aws:s3:::alpha-dev-flow-logs/*"])
    error_message = "The Deny must cover the bucket and its objects"
  }
}

run "tls_only_deny_kept_with_log_delivery" {
  command = plan

  variables {
    log_delivery = ["vended_logs", "vpc_flow_logs"]
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport"
    error_message = "The TLS Deny must stay with log delivery enabled"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 5
    error_message = "Both sources together must give 1 + 2 + 2 statements"
  }
}

run "vended_logs_statements" {
  command = plan

  variables {
    log_delivery = ["vended_logs"]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 3
    error_message = "vended_logs must add two statements"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Principal.Service == "delivery.logs.amazonaws.com"
    error_message = "Write statement must grant delivery.logs.amazonaws.com"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Action == "s3:PutObject"
    error_message = "Write statement must only be s3:PutObject"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Resource == "arn:aws:s3:::alpha-dev-flow-logs/AWSLogs/111111111111/*"
    error_message = "Write statement must be scoped to AWSLogs/<account>"
  }

  assert {
    condition = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition) == jsonencode({
      StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" }
      ArnLike      = { "aws:SourceArn" = "arn:aws:logs:*:111111111111:delivery-source:*" }
    })
    error_message = "Write statement must carry aws:SourceAccount, the ACL condition and an own-account delivery-source aws:SourceArn"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Action) == jsonencode(["s3:GetBucketAcl", "s3:ListBucket"])
    error_message = "Second statement must be s3:GetBucketAcl and s3:ListBucket"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Resource == "arn:aws:s3:::alpha-dev-flow-logs"
    error_message = "The ACL check must apply to the bucket itself"
  }

  assert {
    condition = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Condition) == jsonencode({
      StringEquals = { "aws:SourceAccount" = "111111111111" }
      ArnLike      = { "aws:SourceArn" = "arn:aws:logs:*:111111111111:delivery-source:*" }
    })
    error_message = "The ACL check must carry aws:SourceAccount and aws:SourceArn"
  }
}

run "vpc_flow_logs_statements" {
  command = plan

  variables {
    log_delivery = ["vpc_flow_logs"]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 3
    error_message = "vpc_flow_logs must add two statements"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Principal.Service == "delivery.logs.amazonaws.com"
    error_message = "Write statement must grant delivery.logs.amazonaws.com"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Action == "s3:PutObject"
    error_message = "Write statement must be s3:PutObject"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Resource == "arn:aws:s3:::alpha-dev-flow-logs/AWSLogs/111111111111/*"
    error_message = "Write statement must be scoped to AWSLogs/<account>"
  }

  assert {
    condition     = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition) == jsonencode({ StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" } })
    error_message = "Write statement must carry aws:SourceAccount and the bucket-owner-full-control ACL condition"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Action == "s3:GetBucketAcl"
    error_message = "Second statement must be s3:GetBucketAcl"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Resource == "arn:aws:s3:::alpha-dev-flow-logs"
    error_message = "GetBucketAcl must apply to the bucket itself"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "GetBucketAcl statement must carry aws:SourceAccount"
  }
}

run "no_wildcard_allow_principal" {
  command = plan

  variables {
    log_delivery = ["vended_logs", "vpc_flow_logs"]
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Effect == "Deny" || s.Principal != "*"])
    error_message = "Allow statements must name a specific principal"
  }
}

run "sse_s3_by_default" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Without kms_key_arn the bucket must use AES256"
  }
}

run "sse_kms_when_given" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "With kms_key_arn the bucket must use aws:kms"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "kms_master_key_id must equal the input"
  }
}

run "lifecycle_defaults" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 90
    error_message = "Default expiration must be 90 days"
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days"
  }
}

run "lifecycle_override" {
  command = plan

  variables {
    expiration_days = 14
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 14
    error_message = "expiration_days must be applied"
  }
}

run "force_destroy_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false"
  }
}

run "force_destroy_override" {
  command = plan

  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "force_destroy must follow the input"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.bucket_name == "alpha-dev-flow-logs"
    error_message = "bucket_name must expose the bucket name"
  }

  assert {
    condition     = output.arn == "arn:aws:s3:::alpha-dev-flow-logs"
    error_message = "arn must expose the bucket ARN"
  }

  assert {
    condition     = output.bucket_regional_domain_name == "alpha-dev-flow-logs.s3.ap-northeast-1.amazonaws.com"
    error_message = "bucket_regional_domain_name must be exposed"
  }
}

run "name_rejects_dot" {
  command = plan
  variables { name = "alpha.dev-logs" }
  expect_failures = [var.name]
}

run "name_rejects_uppercase" {
  command = plan
  variables { name = "Alpha-dev-logs" }
  expect_failures = [var.name]
}

run "name_rejects_double_hyphen" {
  command = plan
  variables { name = "alpha--dev-logs" }
  expect_failures = [var.name]
}

run "name_accepts_valid" {
  command = plan
  variables { name = "alpha-dev-flow-logs" }

  assert {
    condition     = aws_s3_bucket.this.bucket == "alpha-dev-flow-logs"
    error_message = "A valid name must be accepted"
  }
}

run "expiration_rejects_zero" {
  command = plan
  variables { expiration_days = 0 }
  expect_failures = [var.expiration_days]
}

run "expiration_rejects_too_large" {
  command = plan
  variables { expiration_days = 3651 }
  expect_failures = [var.expiration_days]
}

run "expiration_accepts_lower_bound" {
  command = plan
  variables { expiration_days = 1 }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 1
    error_message = "1 day must be accepted"
  }
}

run "expiration_accepts_upper_bound" {
  command = plan
  variables { expiration_days = 3650 }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 3650
    error_message = "3650 days must be accepted"
  }
}

run "log_delivery_rejects_unknown" {
  command = plan
  variables { log_delivery = ["cloudtrail"] }
  expect_failures = [var.log_delivery]
}

run "log_delivery_rejects_alb_access_logs" {
  command = plan
  variables { log_delivery = ["alb_access_logs"] }
  expect_failures = [var.log_delivery]
}

run "vended_logs_accept_kms" {
  command = plan

  variables {
    log_delivery = ["vended_logs"]
    kms_key_arn  = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "vended_logs with a customer managed KMS key must be accepted"
  }
}

run "flow_logs_accept_kms" {
  command = plan

  variables {
    log_delivery = ["vpc_flow_logs"]
    kms_key_arn  = "arn:aws:kms:ap-northeast-1:111111111111:key/1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "vpc_flow_logs with a KMS key must be accepted"
  }
}
