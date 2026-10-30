locals {
  # Which condition keys each service accepts is not verified against a real account yet (v7 design section 11).
  # S3 (artifact bucket), CodeBuild and CodePipeline use the key with the caller's IAM permissions (the account root
  # statement of kms-key), so only the services that act on their own are listed: CloudWatch Logs for the build,
  # service and function log groups, CloudWatch and SNS for the alert topic, and EventBridge, which publishes the
  # pipeline-failure events to the encrypted topic.
  # The web bucket is not here (see buckets.tf): it lives in the web stack with SSE-S3, so CloudFront needs no grant.
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
    "events.amazonaws.com"     = {}
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
