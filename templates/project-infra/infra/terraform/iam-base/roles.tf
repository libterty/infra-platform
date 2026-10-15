locals {
  logs_arn_prefix = "arn:aws:logs:${var.aws_region}:${var.expected_account_id}"

  ecr_repository_arns = concat(
    [for s, k in local.service_key : module.in_services.strings["ecr_${k}_arn"]],
    [for m, k in local.mirror_key : module.in_mirrors.strings["ecr_mirror_${k}_arn"]],
  )

  execution_statements = [
    {
      Sid      = "PullImagesFromProjectRepositories"
      Effect   = "Allow"
      Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
      Resource = local.ecr_repository_arns
    },
    {
      # GetAuthorizationToken does not support resource-level permissions; "*" is the only valid Resource.
      Sid      = "EcrLoginToken"
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = "*"
    },
    {
      # Log groups are created by the application stack, so the name pattern of ecs-service (/ecs/<name>) scopes the access.
      Sid      = "WriteServiceLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${local.logs_arn_prefix}:log-group:/ecs/${local.name_prefix}-*:*"
    },
    {
      Sid      = "ReadApplicationSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [module.in.strings["app_secret_arn"]]
    },
    {
      Sid       = "DecryptWithProjectKeyViaSecretsManager"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = [module.in.strings["kms_key_arn"]]
      Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com" } }
    },
  ]

  # Same permissions as the AWS managed policy AmazonRDSEnhancedMonitoringRole, narrowed to the RDSOSMetrics log group.
  # Whether this is enough is not verified against a real account yet (design section 7.3).
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

  roles = {
    ecs_execution = {
      name  = "${local.name_prefix}-ecs-execution"
      trust = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = var.expected_account_id }
      policies = {
        pull-and-log = jsonencode({ Version = "2012-10-17", Statement = local.execution_statements })
      }
    }
    # Trust only. The policy that reads the database secret is attached by iam-app after the secret exists.
    rds_proxy = {
      name     = "${local.name_prefix}-rds-proxy"
      trust    = { service_principals = ["rds.amazonaws.com"], source_account = var.expected_account_id }
      policies = {}
    }
    rds_monitoring = {
      name  = "${local.name_prefix}-rds-monitoring"
      trust = { service_principals = ["monitoring.rds.amazonaws.com"], source_account = var.expected_account_id }
      policies = {
        RDSOSMetrics = jsonencode({ Version = "2012-10-17", Statement = local.monitoring_statements })
      }
    }
  }
}

module "role" {
  source   = "../../../../../modules/iam-role"
  for_each = local.roles

  name            = each.value.name
  trust           = each.value.trust
  inline_policies = each.value.policies
}
