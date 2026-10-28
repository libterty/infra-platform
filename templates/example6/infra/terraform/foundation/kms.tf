locals {
  # Which condition keys each service accepts is not verified against a real account yet (v7 design section 11).
  # Lambda, DynamoDB and Secrets Manager use the key with the caller's IAM permissions (the account root statement of
  # kms-key), so only the services that act on their own are listed: CloudWatch Logs for the log groups of the api
  # stack, and CloudWatch and SNS for the alarm topic.
  kms_service_principals = {
    "logs.${var.aws_region}.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:*"]
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
