locals {
  region     = var.aws_region
  account_id = var.expected_account_id

  # Resource names that other stacks create later are not read from SSM (iam runs before them); they follow the naming
  # rules below, which the operation, agent and application stacks must keep.
  logs_arn_prefix = "arn:aws:logs:${local.region}:${local.account_id}"
  ecr_arns        = jsondecode(module.in.strings["ecr_repository_arns"])
  runtimes        = sort(jsondecode(module.in.strings["agent_runtimes"]))

  # AgentCore names allow underscores only: <project>_<env>_<runtime> and <project>_<env>_memory. The ID AWS adds
  # after the name is generated, so the grants end with -*.
  agentcore_name_prefix = replace(local.name_prefix, "-", "_")
  runtime_names         = [for r in local.runtimes : "${local.agentcore_name_prefix}_${replace(r, "-", "_")}"]
  runtime_arns          = [for n in local.runtime_names : "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:runtime/${n}-*"]
  memory_arn            = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:memory/${local.agentcore_name_prefix}_memory-*"

  # Buckets are created by the operation stack, whose names must be <project>-<env>-<purpose>-<account>.
  import_bucket_arn = "arn:aws:s3:::${local.name_prefix}-import-${local.account_id}"
  eval_bucket_arn   = "arn:aws:s3:::${local.name_prefix}-eval-batch-${local.account_id}"

  # Services whose images ECS pulls with the execution role. The Lambda functions and the Runtimes pull their own.
  ecs_services         = ["api", "worker"]
  ecs_repository_arns  = [for s in local.ecs_services : lookup(local.ecr_arns, s, "")]
  runtime_repositories = [for r in local.runtimes : lookup(local.ecr_arns, r, "")]

  metric_namespace = "${title(var.project)}/${var.env}"

  # Statements shared by several roles.
  db_secret_statements = [
    {
      Sid      = "ReadSecrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [module.in.strings["db_secret_arn"]]
    },
  ]
  decrypt_secrets_statement = {
    Sid       = "DecryptSecrets"
    Effect    = "Allow"
    Action    = ["kms:Decrypt"]
    Resource  = [data.aws_kms_alias.secretsmanager.target_key_arn]
    Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${local.region}.amazonaws.com" } }
  }
  # None of these support resource-level permissions, so "*" is the only valid Resource.
  trace_statement = {
    Sid      = "TraceSegments"
    Effect   = "Allow"
    Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    Resource = "*"
  }
  ecs_exec_statement = {
    Sid      = "EcsExec"
    Effect   = "Allow"
    Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    Resource = "*"
  }
  ecr_login_statement = {
    Sid      = "EcrLoginToken"
    Effect   = "Allow"
    Action   = ["ecr:GetAuthorizationToken"]
    Resource = "*"
  }
  guardrail_statement = {
    Sid      = "ApplyGuardrail"
    Effect   = "Allow"
    Action   = ["bedrock:ApplyGuardrail"]
    Resource = ["arn:aws:bedrock:${local.region}:${local.account_id}:guardrail/*"]
  }

  statements = merge(
    {
      ecs_execution = [
        {
          Sid      = "PullImages"
          Effect   = "Allow"
          Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
          Resource = local.ecs_repository_arns
        },
        local.ecr_login_statement,
        {
          # The log groups are created by the application stack; ecs-service names them /ecs/<service name>.
          Sid      = "WriteServiceLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${local.logs_arn_prefix}:log-group:/ecs/${local.name_prefix}-*:*"]
        },
      ]

      # The api signs tokens with the private key and verifies them with the public key.
      api_task = concat(
        length(local.runtime_arns) == 0 ? [] : [
          {
            Sid      = "InvokeAgentRuntime"
            Effect   = "Allow"
            Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
            Resource = flatten([for a in local.runtime_arns : [a, "${a}/runtime-endpoint/*"]])
          },
        ],
        [
          local.guardrail_statement,
          {
            Sid      = "ReadSecrets"
            Effect   = "Allow"
            Action   = ["secretsmanager:GetSecretValue"]
            Resource = [module.in.strings["db_secret_arn"], module.in.strings["signing_secret_arn"], module.in.strings["app_secret_arn"]]
          },
          local.decrypt_secrets_statement,
          local.trace_statement,
          local.ecs_exec_statement,
        ],
      )

      # The worker only verifies, so it gets the public key and never the private one.
      worker_task = [
        {
          Sid      = "ReadSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [module.in.strings["db_secret_arn"], module.in.strings["signing_secret_arn"]]
        },
        local.decrypt_secrets_statement,
        {
          # PutMetricData cannot be limited by resource, only by namespace.
          Sid       = "PutCustomMetrics"
          Effect    = "Allow"
          Action    = ["cloudwatch:PutMetricData"]
          Resource  = "*"
          Condition = { StringEquals = { "cloudwatch:namespace" = local.metric_namespace } }
        },
        local.trace_statement,
        local.ecs_exec_statement,
      ]

      # One role for both import functions: the bucket and the database are theirs together.
      lambda = concat(
        [
          {
            Sid      = "WriteLogs"
            Effect   = "Allow"
            Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
            Resource = ["${local.logs_arn_prefix}:log-group:/aws/lambda/${local.name_prefix}-import-*:*"]
          },
          {
            Sid      = "VpcNetworkInterfaces"
            Effect   = "Allow"
            Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"]
            Resource = "*"
          },
          {
            Sid      = "ReadWriteImportObjects"
            Effect   = "Allow"
            Action   = ["s3:GetObject", "s3:PutObject"]
            Resource = ["${local.import_bucket_arn}/*"]
          },
          {
            Sid      = "ListImportBucket"
            Effect   = "Allow"
            Action   = ["s3:ListBucket"]
            Resource = [local.import_bucket_arn]
          },
        ],
        local.db_secret_statements,
        [local.decrypt_secrets_statement],
      )
    },
    {
      agent_runtime = concat(
        length(local.runtime_repositories) == 0 ? [] : [
          {
            Sid      = "PullRuntimeImage"
            Effect   = "Allow"
            Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
            Resource = local.runtime_repositories
          },
        ],
        [local.ecr_login_statement],
        length(local.runtime_names) == 0 ? [] : [
          {
            Sid      = "ManageRuntimeLogGroups"
            Effect   = "Allow"
            Action   = ["logs:CreateLogGroup", "logs:DescribeLogStreams"]
            Resource = [for n in local.runtime_names : "${local.logs_arn_prefix}:log-group:/aws/bedrock-agentcore/runtimes/${n}-*"]
          },
          {
            Sid      = "WriteRuntimeLogs"
            Effect   = "Allow"
            Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
            Resource = [for n in local.runtime_names : "${local.logs_arn_prefix}:log-group:/aws/bedrock-agentcore/runtimes/${n}-*:log-stream:*"]
          },
        ],
        [
          local.trace_statement,
          {
            # Cross-region inference profiles route to other regions, so the foundation model ARN has a * region.
            Sid    = "InvokeModels"
            Effect = "Allow"
            Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
            Resource = [
              "arn:aws:bedrock:${local.region}:${local.account_id}:inference-profile/*",
              "arn:aws:bedrock:*::foundation-model/anthropic.*",
            ]
          },
          local.guardrail_statement,
          {
            Sid      = "UseMemory"
            Effect   = "Allow"
            Action   = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:GetEvent", "bedrock-agentcore:RetrieveMemoryRecords"]
            Resource = [local.memory_arn]
          },
        ],
        local.db_secret_statements,
        [local.decrypt_secrets_statement],
      )
    },
    # Batch inference for regression evaluation. The eval data must stay in the dev account, so no other env has it.
    local.is_dev ? {
      eval_batch = [
        {
          Sid       = "ListEvalBucket"
          Effect    = "Allow"
          Action    = ["s3:ListBucket"]
          Resource  = [local.eval_bucket_arn]
          Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
        },
        {
          Sid       = "ReadWriteEvalObjects"
          Effect    = "Allow"
          Action    = ["s3:GetObject", "s3:PutObject"]
          Resource  = ["${local.eval_bucket_arn}/*"]
          Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
        },
        {
          Sid    = "InvokeEvalModel"
          Effect = "Allow"
          Action = ["bedrock:InvokeModel"]
          Resource = [
            "arn:aws:bedrock:${local.region}:${local.account_id}:inference-profile/global.${var.eval_batch_model_id}",
            "arn:aws:bedrock:*::foundation-model/${var.eval_batch_model_id}",
          ]
        },
      ]
    } : {},
  )
}

data "aws_kms_alias" "secretsmanager" {
  name = "alias/aws/secretsmanager"
}
