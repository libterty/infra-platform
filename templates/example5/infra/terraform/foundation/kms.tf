locals {
  # Which condition keys each service accepts is not verified against a real account yet (v7 design section 11).
  kms_service_principals = {
    "logs.${var.aws_region}.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:*"]
      }]
    }
    # VPC flow logs are delivered to the SSE-KMS flow log bucket by log delivery, which needs the full set of actions.
    "delivery.logs.amazonaws.com" = {
      actions = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
      conditions = [{
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [var.expected_account_id]
      }]
    }
    "cloudwatch.amazonaws.com" = {}
    "sns.amazonaws.com"        = {}
  }
}

module "kms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/kms-key/aws"
  version = "~> 0.1.1"

  name               = local.name_prefix
  description        = "Shared key of ${local.name_prefix}"
  service_principals = local.kms_service_principals
}
