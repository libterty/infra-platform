locals {
  # One key for the governance data of the account (design 8.1). The account root statement of kms-key lets IAM grant
  # the roles of the iam stack (Config delivery, Backup) their own use of the key, so only services that act on their
  # own are listed here. Which condition keys each service sends is not yet verified against a real account.
  kms_service_principals = {
    # CloudTrail encrypts log files with the trail ARN as encryption context (design section 4). DescribeKey carries
    # no encryption context, hence IfExists; aws:SourceArn still limits both actions to trails of this account.
    "cloudtrail.amazonaws.com" = {
      actions = ["kms:GenerateDataKey*", "kms:DescribeKey"]
      conditions = [
        {
          test     = "StringLikeIfExists"
          variable = "kms:EncryptionContext:aws:cloudtrail:arn"
          values   = ["arn:aws:cloudtrail:*:${var.expected_account_id}:trail/*"]
        },
        {
          test     = "ArnLike"
          variable = "aws:SourceArn"
          values   = ["arn:aws:cloudtrail:*:${var.expected_account_id}:trail/*"]
        },
      ]
    }
    "config.amazonaws.com" = {}
    "backup.amazonaws.com" = {}
    # Publishers of the encrypted alert topic: Budgets, EventBridge rules (detect) and CloudWatch alarms (audit).
    "budgets.amazonaws.com"    = {}
    "events.amazonaws.com"     = {}
    "cloudwatch.amazonaws.com" = {}
    # The CloudTrail log group of the audit stack.
    "logs.${var.aws_region}.amazonaws.com" = {
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${var.aws_region}:${var.expected_account_id}:log-group:*"]
      }]
    }
  }
}

module "kms" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/kms-key/aws"
  version = "~> 0.1.1"

  name               = "${local.name_prefix}-governance"
  description        = "Governance key of ${local.name_prefix}: CloudTrail, Config, Backup and the alert topic"
  service_principals = local.kms_service_principals
}
