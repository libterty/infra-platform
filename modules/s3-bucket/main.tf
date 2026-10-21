data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  bucket_arn = aws_s3_bucket.this.arn

  tls_only_statement = [{
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }]

  # The for expressions run once when the source is selected and zero times otherwise. This avoids a conditional
  # between a list of objects and [], which Terraform cannot unify.
  vended_selected   = setintersection(var.log_delivery, ["vended_logs"])
  flow_log_selected = setintersection(var.log_delivery, ["vpc_flow_logs"])

  expiration_days = var.never_expire ? null : coalesce(var.expiration_days, 90)

  # CloudWatch Logs adds these statements itself when a delivery is created, but this module owns the whole policy
  # and the next apply would drop them. Delivery sources may live in any region but must belong
  # to this account.
  vended_source_conditions = {
    StringEquals = { "aws:SourceAccount" = local.account_id }
    ArnLike      = { "aws:SourceArn" = "arn:${split(":", local.bucket_arn)[1]}:logs:*:${local.account_id}:delivery-source:*" }
  }

  vended_statements = concat(
    [for _ in local.vended_selected : {
      Sid       = "AllowVendedLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
      Condition = merge(local.vended_source_conditions, {
        StringEquals = merge(local.vended_source_conditions.StringEquals, { "s3:x-amz-acl" = "bucket-owner-full-control" })
      })
    }],
    [for _ in local.vended_selected : {
      Sid       = "AllowVendedLogsAclCheck"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
      Resource  = local.bucket_arn
      Condition = local.vended_source_conditions
    }],
  )

  flow_log_statements = concat(
    [for _ in local.flow_log_selected : {
      Sid       = "AllowVpcFlowLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "s3:x-amz-acl"      = "bucket-owner-full-control"
        }
      }
    }],
    [for _ in local.flow_log_selected : {
      Sid       = "AllowVpcFlowLogsAclCheck"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:GetBucketAcl"
      Resource  = local.bucket_arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }],
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = var.kms_key_arn != null

    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  count = var.versioning == null ? 0 : 1

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # The id stays expire-objects for existing buckets, so switching to v0.1.1 is not a change.
    id     = var.never_expire ? "abort-incomplete-uploads" : "expire-objects"
    status = "Enabled"

    # A null prefix renders the same as an empty filter block.
    filter {
      prefix = var.expiration_prefix
    }

    dynamic "expiration" {
      for_each = var.never_expire ? [] : [local.expiration_days]
      content {
        days = expiration.value
      }
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A separate rule: expired_object_delete_marker cannot share an expiration block with days. It covers the whole
  # bucket so old versions never outlive the retention window, whatever expiration_prefix is.
  dynamic "rule" {
    for_each = var.versioning == null ? [] : [var.versioning]
    content {
      id     = "cleanup-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = rule.value.noncurrent_expiration_days
      }

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # The noncurrent actions only make sense once versioning is on.
  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_notification" "this" {
  count = length(var.lambda_notifications) == 0 ? 0 : 1

  bucket = aws_s3_bucket.this.id

  dynamic "lambda_function" {
    for_each = var.lambda_notifications
    content {
      id                  = lambda_function.key
      lambda_function_arn = lambda_function.value.function_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.tls_only_statement,
      local.vended_statements,
      local.flow_log_statements,
    )
  })

  # Applying the policy before the public access block exists can be rejected as a public policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
