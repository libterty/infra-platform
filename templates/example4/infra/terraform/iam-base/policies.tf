# Permissions of the roles that can be written before the later stacks exist. Every Resource is built from keys that
# foundation, network and storage publish, or from the naming rule below. The action lists follow the AWS service
# documentation and are not yet verified against a real account (design section 11).
locals {
  logs_arn_prefix   = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}"
  glue_arn_prefix   = "arn:aws:glue:${var.aws_region}:${var.expected_account_id}"
  events_arn_prefix = "arn:aws:events:${var.aws_region}:${var.expected_account_id}"
  ec2_arn_prefix    = "arn:aws:ec2:${var.aws_region}:${var.expected_account_id}"

  kms_key_arn            = module.in.strings["kms_key_arn"]
  raw_bucket_arn         = module.in.strings["raw_bucket_arn"]
  curated_bucket_arn     = module.in.strings["curated_bucket_arn"]
  glue_assets_bucket_arn = module.in.strings["glue_assets_bucket_arn"]

  # Naming rule shared with the pipeline stack (design K21, section 7.4): glue-etl creates the workflow with this name
  # and the EventBridge rule and the EVENT trigger as <workflow>-s3-event. The workflow does not exist yet, so its ARN
  # is built from the name; the pipeline tests pin the same strings.
  workflow_name  = "${local.name_prefix}-raw-to-curated"
  workflow_arn   = "${local.glue_arn_prefix}:workflow/${local.workflow_name}"
  event_rule_arn = "${local.events_arn_prefix}:rule/${local.workflow_name}-s3-event"

  # Glue catalog: the catalog root, the database and the tables in it.
  catalog_arns = {
    for layer, db in { raw = module.in.strings["raw_database_name"], curated = module.in.strings["curated_database_name"] } :
    layer => ["${local.glue_arn_prefix}:database/${db}", "${local.glue_arn_prefix}:table/${db}/*"]
  }
  catalog_root_arn = "${local.glue_arn_prefix}:catalog"

  glue_catalog_read_actions = [
    "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables",
    "glue:GetPartition", "glue:GetPartitions", "glue:BatchGetPartition",
  ]
  glue_catalog_write_actions = [
    "glue:CreateTable", "glue:UpdateTable", "glue:DeleteTable",
    "glue:CreatePartition", "glue:BatchCreatePartition", "glue:UpdatePartition", "glue:BatchUpdatePartition",
    "glue:DeletePartition", "glue:BatchDeletePartition",
  ]

  # Which log group names Glue uses with a security configuration is not verified, so the scope is /aws-glue/ only.
  glue_log_group_arn = "${local.logs_arn_prefix}:log-group:/aws-glue/*"

  # The catalog is encrypted with the shared key too (foundation, design D13).
  glue_kms_statement = {
    Sid      = "UseSharedKey"
    Effect   = "Allow"
    Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    Resource = [local.kms_key_arn]
  }

  glue_log_statement = {
    Sid      = "WriteGlueLogs"
    Effect   = "Allow"
    Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    Resource = [local.glue_log_group_arn, "${local.glue_log_group_arn}:log-stream:*"]
  }

  glue_crawler_statements = [
    {
      Sid      = "ReadObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["${local.raw_bucket_arn}/raw/*", "${local.curated_bucket_arn}/*"]
    },
    {
      Sid      = "ListBuckets"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [local.raw_bucket_arn, local.curated_bucket_arn]
    },
    {
      Sid      = "ManageCatalog"
      Effect   = "Allow"
      Action   = concat(local.glue_catalog_read_actions, local.glue_catalog_write_actions)
      Resource = concat([local.catalog_root_arn], local.catalog_arns["raw"], local.catalog_arns["curated"])
    },
    local.glue_log_statement,
    local.glue_kms_statement,
  ]

  glue_job_statements = [
    {
      Sid      = "ReadObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["${local.raw_bucket_arn}/raw/*", "${local.glue_assets_bucket_arn}/scripts/*"]
    },
    {
      Sid      = "ReadWriteObjects"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = ["${local.curated_bucket_arn}/*", "${local.glue_assets_bucket_arn}/tmp/*"]
    },
    {
      Sid      = "ListBuckets"
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [local.raw_bucket_arn, local.curated_bucket_arn, local.glue_assets_bucket_arn]
    },
    {
      Sid      = "ReadRawCatalog"
      Effect   = "Allow"
      Action   = local.glue_catalog_read_actions
      Resource = concat([local.catalog_root_arn], local.catalog_arns["raw"])
    },
    {
      Sid      = "ManageCuratedCatalog"
      Effect   = "Allow"
      Action   = concat(local.glue_catalog_read_actions, local.glue_catalog_write_actions)
      Resource = concat([local.catalog_root_arn], local.catalog_arns["curated"])
    },
    {
      # Jobs are created by the pipeline stack, so the project's name prefix scopes them.
      Sid      = "UseJobBookmarks"
      Effect   = "Allow"
      Action   = ["glue:GetJobBookmark", "glue:UpdateJobBookmark"]
      Resource = ["${local.glue_arn_prefix}:job/${local.name_prefix}-*"]
    },
    local.glue_log_statement,
    local.glue_kms_statement,
  ]

  glue_events_statements = [
    {
      Sid      = "NotifyWorkflowEvent"
      Effect   = "Allow"
      Action   = ["glue:notifyEvent"]
      Resource = [local.workflow_arn]
    },
  ]

  redshift_statements = [
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
      Sid      = "ReadCuratedCatalog"
      Effect   = "Allow"
      Action   = local.glue_catalog_read_actions
      Resource = concat([local.catalog_root_arn], local.catalog_arns["curated"])
    },
    {
      Sid      = "DecryptWithSharedKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [local.kms_key_arn]
    },
  ]

  # A QuickSight VPC connection creates its network interfaces in the subnets of this VPC (both tiers: which tier the bi
  # stack uses is decided there) with the QuickSight security group of the network stack.
  quicksight_vpc_statements = [
    {
      Sid    = "ManageConnectionNetworkInterfaces"
      Effect = "Allow"
      Action = ["ec2:CreateNetworkInterface", "ec2:ModifyNetworkInterfaceAttribute", "ec2:DeleteNetworkInterface"]
      Resource = concat(
        ["${local.ec2_arn_prefix}:network-interface/*"],
        [for s in concat(module.in.lists["subnet_ids_app"], module.in.lists["subnet_ids_data"]) : "${local.ec2_arn_prefix}:subnet/${s}"],
        ["${local.ec2_arn_prefix}:security-group/${module.in.strings["sg_quicksight_id"]}"],
      )
    },
    {
      # Describe actions do not support resource-level permissions; "*" is the only valid Resource.
      Sid      = "DescribeNetwork"
      Effect   = "Allow"
      Action   = ["ec2:DescribeSubnets", "ec2:DescribeSecurityGroups"]
      Resource = ["*"]
    },
  ]
}
