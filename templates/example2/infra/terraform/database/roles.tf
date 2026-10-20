locals {
  logs_arn_prefix = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}"

  # Same permissions as the AWS managed policy AmazonRDSEnhancedMonitoringRole, narrowed to the RDSOSMetrics log group.
  monitoring_statements = [
    {
      Sid      = "ManageRdsOsMetricsLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:PutRetentionPolicy"]
      Resource = "${local.logs_arn_prefix}:log-group:RDSOSMetrics:*"
    },
    {
      Sid      = "WriteRdsOsMetricsStreams"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:GetLogEvents"]
      Resource = "${local.logs_arn_prefix}:log-group:RDSOSMetrics:log-stream:*"
    },
  ]

  # The Proxy signs in to the cluster with the master user secret RDS keeps, which is encrypted with the AWS managed
  # Secrets Manager key because neither the cluster nor foundation names another key.
  proxy_statements = [
    {
      Sid      = "GetClusterSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [module.db.master_user_secret_arn]
    },
    {
      Sid       = "DecryptThroughSecretsManager"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = [data.aws_kms_alias.secretsmanager.target_key_arn]
      Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com" } }
    },
  ]
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}

# The Proxy role's policy needs the cluster's secret ARN and the cluster module needs the role ARN for its Proxy.
# That is not a cycle: the secret ARN comes from the cluster resource, the role ARN is only used by the Proxy
# resources, which are created after the cluster (design section 7, R2).
module "proxy_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.2.0"

  name  = "${local.name_prefix}-rds-proxy"
  trust = { service_principals = ["rds.amazonaws.com"], source_account = var.expected_account_id }
  inline_policies = {
    cluster-secret = jsonencode({ Version = "2012-10-17", Statement = local.proxy_statements })
  }
}

module "monitoring_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.2.0"

  name  = "${local.name_prefix}-rds-monitoring"
  trust = { service_principals = ["monitoring.rds.amazonaws.com"], source_account = var.expected_account_id }
  inline_policies = {
    RDSOSMetrics = jsonencode({ Version = "2012-10-17", Statement = local.monitoring_statements })
  }
}
