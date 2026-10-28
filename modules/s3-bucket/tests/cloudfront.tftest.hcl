mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values = {
    arn                         = "arn:aws:s3:::alpha-dev-web"
    bucket                      = "alpha-dev-web"
    bucket_regional_domain_name = "alpha-dev-web.s3.ap-northeast-1.amazonaws.com"
  }
}

variables {
  name         = "alpha-dev-web"
  never_expire = true
}

run "no_distribution_keeps_the_previous_policy" {
  command = plan

  assert {
    condition = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy)) == jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::alpha-dev-web", "arn:aws:s3:::alpha-dev-web/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    })
    error_message = "Without cloudfront_distribution_arns the policy must be the TLS-only policy of 0.4.0"
  }
}

run "distribution_arns_add_one_read_statement" {
  command = plan

  variables {
    cloudfront_distribution_arns = [
      "arn:aws:cloudfront::111111111111:distribution/E2ABCDEFGHIJKL",
      "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL",
    ]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2
    error_message = "Distribution ARNs must add exactly one statement"
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport"
    error_message = "The TLS Deny must stay first"
  }

  assert {
    condition = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[1]) == jsonencode({
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::alpha-dev-web/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = [
            "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL",
            "arn:aws:cloudfront::111111111111:distribution/E2ABCDEFGHIJKL",
          ]
        }
      }
    })
    error_message = "The CloudFront statement must allow only s3:GetObject on objects for the listed distributions"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "Public access block must stay on with CloudFront access"
  }
}

run "duplicate_distribution_arns_collapse" {
  command = plan

  variables {
    cloudfront_distribution_arns = [
      "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL",
      "arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL",
    ]
  }

  assert {
    condition     = jsonencode(jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Condition.StringEquals["AWS:SourceArn"]) == jsonencode(["arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"])
    error_message = "Duplicate ARNs must appear once"
  }
}

run "cloudfront_statement_comes_after_log_delivery" {
  command = plan

  variables {
    never_expire                 = false
    log_delivery                 = ["vended_logs"]
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"]
  }

  assert {
    condition     = [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "AllowVendedLogsWrite", "AllowVendedLogsAclCheck", "AllowCloudFrontRead"]
    error_message = "Existing statements must keep their positions and the CloudFront statement must come last"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Effect == "Deny" || s.Principal != "*"])
    error_message = "Allow statements must name a specific principal"
  }
}

run "other_partition_is_accepted" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws-cn:cloudfront::111111111111:distribution/E1ABCDEFGHIJKL"]
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2
    error_message = "A distribution ARN in another partition must be accepted"
  }
}

run "distribution_in_another_account_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::222222222222:distribution/E1ABCDEFGHIJKL"]
  }

  expect_failures = [aws_s3_bucket_policy.this]
}

run "bucket_arn_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:s3:::alpha-dev-web"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "cloudfront_function_arn_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111111111111:function/alpha-dev-rewrite"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "distribution_arn_with_region_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront:us-east-1:111111111111:distribution/E1ABCDEFGHIJKL"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "distribution_arn_with_short_account_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::11111111111:distribution/E1ABCDEFGHIJKL"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "distribution_id_wildcard_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::111111111111:distribution/*"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}
