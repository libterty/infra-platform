# The firehose role is created by iam-base with a trust policy only, because the OpenSearch domain ARN does not exist
# before the search stack. This stack attaches the policy. The action lists follow the AWS Firehose and OpenSearch
# documentation and are not yet verified against a real account (v7 design section 11).
locals {
  logs_arn_prefix = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}"
  ec2_arn_prefix  = "arn:aws:ec2:${var.aws_region}:${var.expected_account_id}"

  role_firehose_arn    = module.in.strings["role_firehose_arn"]
  kms_key_arn          = module.in.strings["kms_key_arn"]
  telemetry_bucket_arn = module.in.strings["telemetry_bucket_arn"]
  domain_arn           = module.in.strings["opensearch_domain_arn"]

  # firehose-stream names its log group /aws/kinesisfirehose/<stream name>; the ingest stack names the streams
  # <name_prefix>-<purpose>, so this prefix covers both streams and nothing else.
  firehose_log_group_arn = "${local.logs_arn_prefix}:log-group:/aws/kinesisfirehose/${local.name_prefix}-*"

  # Which tier the delivery stream uses is decided by the ingest stack, so both tiers are allowed (same as the
  # sagemaker_endpoint role in iam-base).
  firehose_subnet_arns = [
    for s in concat(module.in.lists["subnet_ids_app"], module.in.lists["subnet_ids_data"]) : "${local.ec2_arn_prefix}:subnet/${s}"
  ]

  firehose_statement_list = [
    {
      Sid      = "ReadStream"
      Effect   = "Allow"
      Action   = ["kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards"]
      Resource = [module.in.strings["stream_arn"]]
    },
    {
      # Prefixes only: the telemetry bucket as a whole is never writable (v7 design section 4, trust boundary).
      Sid      = "WriteTelemetryObjects"
      Effect   = "Allow"
      Action   = ["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"]
      Resource = ["${local.telemetry_bucket_arn}/raw/*", "${local.telemetry_bucket_arn}/errors/*"]
    },
    {
      Sid      = "ListTelemetryBucket"
      Effect   = "Allow"
      Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
      Resource = [local.telemetry_bucket_arn]
    },
    {
      Sid      = "DescribeDomain"
      Effect   = "Allow"
      Action   = ["es:DescribeDomain", "es:DescribeDomains", "es:DescribeDomainConfig"]
      Resource = [local.domain_arn, "${local.domain_arn}/*"]
    },
    {
      Sid      = "WriteDomain"
      Effect   = "Allow"
      Action   = ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet"]
      Resource = ["${local.domain_arn}/*"]
    },
    {
      # Describe actions do not support resource-level permissions; "*" is the only valid Resource.
      Sid      = "DescribeNetwork"
      Effect   = "Allow"
      Action   = ["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeNetworkInterfaces"]
      Resource = ["*"]
    },
    {
      Sid    = "CreateNetworkInterface"
      Effect = "Allow"
      Action = ["ec2:CreateNetworkInterface"]
      Resource = concat(
        ["${local.ec2_arn_prefix}:network-interface/*"],
        local.firehose_subnet_arns,
        ["${local.ec2_arn_prefix}:security-group/${module.in.strings["sg_firehose_id"]}"],
      )
    },
    {
      Sid      = "ManageNetworkInterface"
      Effect   = "Allow"
      Action   = ["ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface"]
      Resource = ["${local.ec2_arn_prefix}:network-interface/*"]
    },
    {
      Sid      = "UseSharedKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      Resource = [local.kms_key_arn]
    },
    {
      # firehose-stream creates the log streams; the role only writes events.
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:PutLogEvents"]
      Resource = [local.firehose_log_group_arn, "${local.firehose_log_group_arn}:log-stream:*"]
    },
  ]


  # Keyed by Sid so the tests can address one statement; the policy document lists them in Sid order.
  firehose_statements = { for s in local.firehose_statement_list : s.Sid => s }

  firehose_policies = {
    delivery = jsonencode({ Version = "2012-10-17", Statement = values(local.firehose_statements) })
  }
}

module "firehose_policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role-policy/aws"
  version = "~> 0.1.1"

  role_arn = local.role_firehose_arn
  policies = local.firehose_policies
}
