data "aws_caller_identity" "current" {}

# Only ALB access logs need the regional ELB service account.
data "aws_elb_service_account" "this" {
  count = contains(var.log_delivery, "alb_access_logs") ? 1 : 0
}

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
  alb_selected      = setintersection(var.log_delivery, ["alb_access_logs"])
  flow_log_selected = setintersection(var.log_delivery, ["vpc_flow_logs"])

  expiration_days = var.never_expire ? null : coalesce(var.expiration_days, 90)

  # Regions opened before 2022-08 (e.g. ap-northeast-1) write through a regional ELB account; newer ones use the
  # service principal. Granting both avoids Access Denied in either case.
  alb_statements = concat(
    [for _ in local.alb_selected : {
      Sid       = "AllowELBServiceAccountLogDelivery"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.this[0].arn }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/*AWSLogs/${local.account_id}/*"
    }],
    [for _ in local.alb_selected : {
      Sid       = "AllowELBLogDeliveryServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/*AWSLogs/${local.account_id}/*"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
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

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # The id stays expire-objects for existing buckets, so switching to v0.2.0 is not a change.
    id     = var.never_expire ? "abort-incomplete-uploads" : "expire-objects"
    status = "Enabled"

    filter {}

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
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.tls_only_statement,
      local.alb_statements,
      local.flow_log_statements,
    )
  })

  # Applying the policy before the public access block exists can be rejected as a public policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
