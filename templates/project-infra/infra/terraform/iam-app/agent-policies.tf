# Second step of the two-step IAM: iam-base created the roles before the agent stack, and the permissions are attached
# here with the exact ARNs that agent published. No model ARN is assembled here; invoke_arns comes from agent.
locals {
  runtime_grants = { for r, k in local.agent_key : r => jsondecode(module.in_agents.strings["agent_runtime_${k}"]) }

  # STANDARD guardrails are also evaluated through their profile, in a region AWS picks, so the region is "*" and only
  # the profile id is exact.
  guardrail_resources = {
    for g, v in local.agent_guardrails : g => concat(
      [v.arn],
      v.profile_id == null ? [] : ["arn:aws:bedrock:*:${var.expected_account_id}:guardrail-profile/${v.profile_id}"],
    )
  }

  # Unknown keys resolve to nothing here; guards.tf reports them.
  agent_grants = merge(
    { for r, g in local.runtime_grants : "runtime/${r}" => { models = g.models, guardrails = g.guardrails } },
    { for s, a in var.agent_access : "service/${s}" => { models = a.models, guardrails = a.guardrails } },
  )

  # The same model and guardrail statements for Runtime execution roles and task roles. Converse and ConverseStream
  # are authorized by the two InvokeModel actions. Cross-account replaces model access with assuming the role in account B.
  shared_agent_statements = {
    for p, g in local.agent_grants : p => concat(
      length(g.models) == 0 ? [] : [
        local.bedrock_invoke.enabled ? {
          Sid      = "AssumeModelRole"
          Effect   = "Allow"
          Action   = ["sts:AssumeRole"]
          Resource = [local.bedrock_invoke.role_arn]
          } : {
          Sid      = "InvokeModels"
          Effect   = "Allow"
          Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
          Resource = distinct(flatten([for m in g.models : try(local.agent_models[m].invoke_arns, [])]))
        },
      ],
      length(g.guardrails) == 0 ? [] : [{
        Sid      = "ApplyGuardrails"
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = distinct(flatten([for x in g.guardrails : try(local.guardrail_resources[x], [])]))
      }],
    )
  }

  agent_db_runtimes = toset(try(jsondecode(module.in.strings["agent_data_access"])["db"], []))

  runtime_statements = {
    for r, g in local.runtime_grants : r => concat(
      local.shared_agent_statements["runtime/${r}"],
      length(g.memories) == 0 ? [] : [{
        Sid      = "UseMemories"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:CreateEvent", "bedrock-agentcore:ListEvents", "bedrock-agentcore:GetEvent", "bedrock-agentcore:RetrieveMemoryRecords"]
        Resource = [for m in g.memories : local.agent_memories[m].arn]
      }],
      # Not verified: RetrieveAndGenerate also calls a model, which needs the model statement above.
      length(g.knowledge_bases) == 0 ? [] : [{
        Sid      = "QueryKnowledgeBases"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = [for k in g.knowledge_bases : local.agent_knowledge_bases[k].arn]
      }],
      g.gateway ? [{
        Sid      = "InvokeGateway"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeGateway"]
        Resource = [local.agent_gateway.arn]
      }] : [],
      [for st in local.db_secret_statements : st if local.database.enabled && contains(local.agent_db_runtimes, r)],
      g.tracing ? [{
        # X-Ray does not support resource-level permissions; "*" is the only valid Resource. PutSpans is what OTLP to X-Ray needs.
        Sid      = "XRayTraces"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:PutSpans"]
        Resource = "*"
      }] : [],
      [{
        # PutMetricData does not support resource-level permissions; the namespace condition limits it instead.
        Sid       = "PutAgentCoreMetrics"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" } }
      }],
      # Not verified. Older agent JSON has no workload_identity field, which means false.
      try(g.workload_identity, false) ? [{
        Sid    = "GetWorkloadAccessTokens"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId",
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${var.expected_account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${var.aws_region}:${var.expected_account_id}:workload-identity-directory/default/workload-identity/*",
        ]
      }] : [],
    )
  }

  agent_runtime_policies = {
    for r, k in local.agent_key : r => {
      role_arn = module.in_agents.strings["role_agent_${k}_execution_arn"]
      policies = { agent = jsonencode({ Version = "2012-10-17", Statement = local.runtime_statements[r] }) }
    }
  }

  service_agent_statements = {
    for s, a in var.agent_access : s => concat(
      length(a.runtimes) == 0 ? [] : [{
        Sid      = "InvokeAgentRuntimes"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
        Resource = flatten([for r in a.runtimes : try([local.runtime_grants[r].arn, "${local.runtime_grants[r].arn}/runtime-endpoint/*"], [])])
      }],
      local.shared_agent_statements["service/${s}"],
      length(a.knowledge_bases) == 0 ? [] : [{
        Sid      = "QueryKnowledgeBases"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = [for k in a.knowledge_bases : try(local.agent_knowledge_bases[k].arn, "")]
      }],
    )
  }
}

module "agent_runtime_policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role-policy/aws"
  version  = "~> 0.1.0"
  for_each = local.agent_runtime_policies

  role_arn = each.value.role_arn
  policies = each.value.policies
}

# One role for every knowledge base (the role exists before the agent stack knows the list). It reads the dedicated
# database secret of each knowledge base, never the master secret, and only the corpus bucket of each knowledge base.
locals {
  # S3 ARNs carry no account, so a bucket name taken over in another account would otherwise match.
  same_account_condition = { StringEquals = { "aws:ResourceAccount" = var.expected_account_id } }

  kb_secret_arns = sort(distinct([for kb in values(local.agent_knowledge_bases) : kb.credentials_secret_arn]))

  # A knowledge base with a data source that has no prefix reads its whole bucket.
  corpus_prefixes = {
    for k, kb in local.agent_knowledge_bases : k => (
      anytrue([for p in values(kb.inclusion_prefixes) : length(p) == 0]) ? [] : sort(distinct(flatten(values(kb.inclusion_prefixes))))
    )
  }

  bedrock_kb_statements = concat(
    [
      {
        Sid      = "EmbedDocuments"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = distinct(flatten([for kb in values(local.agent_knowledge_bases) : local.agent_models[kb.embedding_model].invoke_arns]))
      },
      {
        Sid      = "UseDataApi"
        Effect   = "Allow"
        Action   = ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement"]
        Resource = [try(local.database.cluster_arn, null)]
      },
      {
        Sid      = "DescribeCluster"
        Effect   = "Allow"
        Action   = ["rds:DescribeDBClusters"]
        Resource = [try(local.database.cluster_arn, null)]
      },
      {
        Sid      = "ReadKnowledgeBaseUserSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.kb_secret_arns
      },
      {
        # The project creates the secrets with the project key (see the guide); an AWS managed key needs no statement.
        Sid      = "DecryptKnowledgeBaseUserSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = module.in.strings["kms_key_arn"]
        Condition = { StringEquals = {
          "kms:ViaService"                  = "secretsmanager.${var.aws_region}.amazonaws.com"
          "kms:EncryptionContext:SecretARN" = local.kb_secret_arns
        } }
      },
    ],
    [for k, kb in local.agent_knowledge_bases : {
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = [kb.bucket_arn]
      Condition = merge(
        local.same_account_condition,
        length(local.corpus_prefixes[k]) == 0 ? {} : { StringLike = { "s3:prefix" = [for p in local.corpus_prefixes[k] : "${p}*"] } },
      )
    }],
    [for k, kb in local.agent_knowledge_bases : {
      Effect    = "Allow"
      Action    = ["s3:GetObject"]
      Resource  = length(local.corpus_prefixes[k]) == 0 ? ["${kb.bucket_arn}/*"] : [for p in local.corpus_prefixes[k] : "${kb.bucket_arn}/${p}*"]
      Condition = local.same_account_condition
    }],
  )

  bedrock_kb_policy = length(local.agent_knowledge_bases) == 0 ? {} : {
    bedrock_kb = {
      role_arn = module.in_agents.strings["role_bedrock_kb_arn"]
      policies = { knowledge-bases = jsonencode({ Version = "2012-10-17", Statement = local.bedrock_kb_statements }) }
    }
  }

  # Lambda targets are invoked with the gateway role; versions and aliases are <arn>:<qualifier>.
  agentcore_gateway_policy = length(local.gateway_lambda_arns) == 0 ? {} : {
    agentcore_gateway = {
      role_arn = module.in_agents.strings["role_agentcore_gateway_arn"]
      policies = { lambda-targets = jsonencode({ Version = "2012-10-17", Statement = concat(
        [{
          Sid      = "InvokeLambdaTargets"
          Effect   = "Allow"
          Action   = ["lambda:InvokeFunction"]
          Resource = concat(local.gateway_lambda_arns, [for a in local.gateway_lambda_arns : "${a}:*"])
        }],
        # The gateway reads the tool schema of a Lambda target from S3 when the target is created.
        length(local.gateway_tool_schema_arns) == 0 ? [] : [{
          Sid       = "ReadToolSchemas"
          Effect    = "Allow"
          Action    = ["s3:GetObject"]
          Resource  = local.gateway_tool_schema_arns
          Condition = local.same_account_condition
        }],
      ) }) }
    }
  }
}

module "agent_service_policy" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role-policy/aws"
  version  = "~> 0.1.0"
  for_each = merge(local.bedrock_kb_policy, local.agentcore_gateway_policy)

  role_arn = each.value.role_arn
  policies = each.value.policies
}
