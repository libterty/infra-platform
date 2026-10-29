# Permissions AWS_ConfigRole and the trail role lack. Every Resource comes from a key foundation publishes or from the
# naming rule in naming.tf. The action lists follow the AWS service documentation and are not yet verified against a
# real account.
locals {
  kms_key_arn       = module.in.strings["kms_key_arn"]
  config_bucket_arn = "arn:aws:s3:::${module.in.strings["config_bucket_name"]}"

  config_statement_list = [
    {
      Sid      = "CheckBucketAcl"
      Effect   = "Allow"
      Action   = ["s3:GetBucketAcl"]
      Resource = [local.config_bucket_arn]
    },
    {
      # The delivery channel writes under AWSLogs/<account>/Config/ (s3-bucket log_delivery config).
      Sid       = "DeliverToConfigBucket"
      Effect    = "Allow"
      Action    = ["s3:PutObject", "s3:PutObjectAcl"]
      Resource  = ["${local.config_bucket_arn}/AWSLogs/${var.expected_account_id}/Config/*"]
      Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
    },
    {
      # The config bucket is encrypted with the governance key.
      Sid      = "EncryptWithGovernanceKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = [local.kms_key_arn]
    },
  ]

  trail_logs_statement_list = [
    {
      # The audit stack creates the log group, so the role only creates streams and writes events in it.
      Sid      = "WriteTrailLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["${local.trail_log_group_arn}:log-stream:*"]
    },
  ]

  # Keyed by Sid so the tests can address one statement; the policy documents list them in Sid order.
  config_statements     = { for s in local.config_statement_list : s.Sid => s }
  trail_logs_statements = { for s in local.trail_logs_statement_list : s.Sid => s }

  role_policies = {
    config     = { permissions = jsonencode({ Version = "2012-10-17", Statement = values(local.config_statements) }) }
    trail_logs = { permissions = jsonencode({ Version = "2012-10-17", Statement = values(local.trail_logs_statements) }) }
  }
}

module "policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role-policy/aws"
  version  = "~> 0.1.1"
  for_each = local.role_policies

  role_arn = module.role[each.key].arn
  policies = each.value
}
