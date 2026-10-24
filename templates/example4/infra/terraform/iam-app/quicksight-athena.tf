# Created here, not in iam-base: only the bi stack uses it, and its policy needs the workgroup ARN from analytics.
# The action lists follow the AWS Athena and QuickSight documentation and are not yet verified against a real
# account (design section 11).
locals {
  glue_arn_prefix = "arn:aws:glue:${var.aws_region}:${var.expected_account_id}"

  curated_bucket_arn = module.in.strings["curated_bucket_arn"]
  results_bucket_arn = module.in.strings["athena_results_bucket_arn"]
  curated_database   = module.in.strings["curated_database_name"]

  quicksight_athena_statement_list = [
    {
      Sid    = "QueryWorkgroup"
      Effect = "Allow"
      Action = [
        "athena:GetWorkGroup", "athena:StartQueryExecution", "athena:StopQueryExecution", "athena:GetQueryExecution",
        "athena:GetQueryResults", "athena:GetQueryResultsStream", "athena:ListQueryExecutions", "athena:BatchGetQueryExecution",
      ]
      Resource = [module.in.strings["athena_workgroup_arn"]]
    },
    {
      Sid      = "ReadCuratedObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["${local.curated_bucket_arn}/*"]
    },
    {
      Sid      = "ListCuratedBucket"
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
      Resource = [local.curated_bucket_arn]
    },
    {
      Sid      = "ReadWriteResults"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
      Resource = ["${local.results_bucket_arn}/*"]
    },
    {
      Sid      = "ListResultsBucket"
      Effect   = "Allow"
      Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
      Resource = [local.results_bucket_arn]
    },
    {
      Sid    = "ReadCuratedCatalog"
      Effect = "Allow"
      Action = [
        "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables",
        "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition",
      ]
      Resource = [
        "${local.glue_arn_prefix}:catalog",
        "${local.glue_arn_prefix}:database/${local.curated_database}",
        "${local.glue_arn_prefix}:table/${local.curated_database}/*",
      ]
    },
    {
      Sid      = "UseSharedKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      Resource = [local.kms_key_arn]
    },
  ]


  # Keyed by Sid so the tests can address one statement; the policy document lists them in Sid order.
  quicksight_athena_statements = { for s in local.quicksight_athena_statement_list : s.Sid => s }

  quicksight_athena_role = {
    name  = "${local.name_prefix}-quicksight-athena"
    trust = { service_principals = ["quicksight.amazonaws.com"], source_account = var.expected_account_id, source_arn = null }
    policies = {
      query-curated = jsonencode({ Version = "2012-10-17", Statement = values(local.quicksight_athena_statements) })
    }
  }
}

module "quicksight_athena_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.4.1"

  name            = local.quicksight_athena_role.name
  trust           = local.quicksight_athena_role.trust
  inline_policies = local.quicksight_athena_role.policies
}
