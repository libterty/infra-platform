mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-audit-logs"
    bucket                      = "alpha-dev-audit-logs"
    bucket_regional_domain_name = "alpha-dev-audit-logs.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name = "alpha-dev-audit-logs"
}

# The policy rendered by 0.5.0 for every pre-existing source; no new input may change it.
run "policy_without_new_types_equals_previous_version" {
  command = plan

  variables {
    log_delivery                 = ["vended_logs", "vpc_flow_logs"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"]
  }

  assert {
    condition = aws_s3_bucket_policy.this.policy == jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = ["arn:aws:s3:::alpha-dev-audit-logs", "arn:aws:s3:::alpha-dev-audit-logs/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
        {
          Sid       = "AllowVendedLogsWrite"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/111111111111/*"
          Condition = {
            StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" }
            ArnLike      = { "aws:SourceArn" = "arn:aws:logs:*:111111111111:delivery-source:*" }
          }
        },
        {
          Sid       = "AllowVendedLogsAclCheck"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
          Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
          Condition = {
            StringEquals = { "aws:SourceAccount" = "111111111111" }
            ArnLike      = { "aws:SourceArn" = "arn:aws:logs:*:111111111111:delivery-source:*" }
          }
        },
        {
          Sid       = "AllowVpcFlowLogsWrite"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/111111111111/*"
          Condition = { StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" } }
        },
        {
          Sid       = "AllowVpcFlowLogsAclCheck"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = "s3:GetBucketAcl"
          Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
          Condition = { StringEquals = { "aws:SourceAccount" = "111111111111" } }
        },
        {
          Sid       = "AllowCloudFrontRead"
          Effect    = "Allow"
          Principal = { Service = "cloudfront.amazonaws.com" }
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::alpha-dev-audit-logs/*"
          Condition = { StringEquals = { "AWS:SourceArn" = ["arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"] } }
        },
      ]
    })
    error_message = "Without cloudtrail, config or organization_id the policy must be byte-identical to 0.5.0"
  }
}

run "cloudtrail_statements" {
  command = plan

  variables {
    log_delivery = ["cloudtrail"]
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "AllowCloudTrailWrite", "AllowCloudTrailAclCheck"]
    error_message = "cloudtrail must add a write and an ACL check statement after the TLS Deny"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1] == {
      Sid       = "AllowCloudTrailWrite"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/111111111111/*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:cloudtrail:*:111111111111:trail/*" }
      }
    }
    error_message = "CloudTrail write must be PutObject on AWSLogs/<account>/* with the ACL, SourceAccount and own-account trail SourceArn conditions"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2] == {
      Sid       = "AllowCloudTrailAclCheck"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "s3:GetBucketAcl"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
      Condition = {
        StringEquals = { "aws:SourceAccount" = "111111111111" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:cloudtrail:*:111111111111:trail/*" }
      }
    }
    error_message = "CloudTrail ACL check must be GetBucketAcl on the bucket with SourceAccount and SourceArn"
  }
}

run "config_statements" {
  command = plan

  variables {
    log_delivery = ["config"]
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "AllowConfigWrite", "AllowConfigAclCheck"]
    error_message = "config must add a write and an ACL check statement after the TLS Deny"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[1] == {
      Sid       = "AllowConfigWrite"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/111111111111/Config/*"
      Condition = { StringEquals = { "aws:SourceAccount" = "111111111111", "s3:x-amz-acl" = "bucket-owner-full-control" } }
    }
    error_message = "Config write must be PutObject on AWSLogs/<account>/Config/* with the ACL and SourceAccount conditions"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2] == {
      Sid       = "AllowConfigAclCheck"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
      Condition = { StringEquals = { "aws:SourceAccount" = "111111111111" } }
    }
    error_message = "Config checks must be GetBucketAcl and ListBucket on the bucket with SourceAccount"
  }
}

run "organization_paths" {
  command = plan

  variables {
    log_delivery    = ["cloudtrail", "config"]
    organization_id = "o-exampleorgid"
  }

  assert {
    condition = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == [
      "DenyInsecureTransport",
      "AllowCloudTrailWrite", "AllowCloudTrailAclCheck", "AllowCloudTrailOrganizationWrite", "AllowCloudTrailOrganizationAclCheck",
      "AllowConfigWrite", "AllowConfigAclCheck", "AllowConfigOrganizationWrite", "AllowConfigOrganizationAclCheck",
    ]
    error_message = "organization_id must add organization statements next to the account statements"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[3] == {
      Sid       = "AllowCloudTrailOrganizationWrite"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/o-exampleorgid/*"
      Condition = { StringEquals = { "aws:SourceOrgID" = "o-exampleorgid", "s3:x-amz-acl" = "bucket-owner-full-control" } }
    }
    error_message = "Organization trail write must be PutObject on AWSLogs/<org id>/* limited by aws:SourceOrgID"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[4] == {
      Sid       = "AllowCloudTrailOrganizationAclCheck"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "s3:GetBucketAcl"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
      Condition = { StringEquals = { "aws:SourceOrgID" = "o-exampleorgid" } }
    }
    error_message = "Organization trail ACL check must be limited by aws:SourceOrgID"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[7] == {
      Sid       = "AllowConfigOrganizationWrite"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs/AWSLogs/*/Config/*"
      Condition = { StringEquals = { "aws:SourceOrgID" = "o-exampleorgid", "s3:x-amz-acl" = "bucket-owner-full-control" } }
    }
    error_message = "Organization Config write must be PutObject on AWSLogs/*/Config/* limited by aws:SourceOrgID"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this.policy).Statement[8] == {
      Sid       = "AllowConfigOrganizationAclCheck"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
      Resource  = "arn:aws:s3:::alpha-dev-audit-logs"
      Condition = { StringEquals = { "aws:SourceOrgID" = "o-exampleorgid" } }
    }
    error_message = "Organization Config checks must be limited by aws:SourceOrgID"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Effect == "Deny" || s.Principal != "*"])
    error_message = "Allow statements must name a specific principal"
  }
}

run "audit_sources_come_before_cloudfront" {
  command = plan

  variables {
    log_delivery                 = ["vended_logs", "cloudtrail"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"]
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "AllowVendedLogsWrite", "AllowVendedLogsAclCheck", "AllowCloudTrailWrite", "AllowCloudTrailAclCheck", "AllowCloudFrontRead"]
    error_message = "Existing statements keep their positions; audit statements go between them and CloudFront"
  }
}

run "audit_bucket_accepts_versioning" {
  command = plan

  variables {
    log_delivery    = ["cloudtrail", "config"]
    expiration_days = 365
    versioning      = {}
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 1
    error_message = "cloudtrail and config buckets hold audit evidence and must accept versioning"
  }
}

run "versioning_with_vended_and_audit_rejected" {
  command = plan

  variables {
    log_delivery = ["cloudtrail", "vended_logs"]
    versioning   = {}
  }

  expect_failures = [var.versioning]
}

run "organization_id_bad_format_rejected" {
  command = plan

  variables {
    log_delivery    = ["cloudtrail"]
    organization_id = "exampleorgid"
  }

  expect_failures = [var.organization_id]
}

run "organization_id_without_audit_source_rejected" {
  command = plan

  variables {
    log_delivery    = ["vended_logs"]
    organization_id = "o-exampleorgid"
  }

  expect_failures = [var.organization_id]
}
