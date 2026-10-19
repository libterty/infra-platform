# Two-step IAM, like the RDS Proxy role: these roles exist before the agent stack so it can pass their ARNs, and
# iam-app attaches the permissions that point at exact agent ARNs afterwards.
locals {
  # The agent stack names the Runtime <project>_<env>_<name>; AgentCore writes the Runtime logs under that name.
  agent_runtime_names = { for r in keys(local.agent_key) : r => replace("${local.name_prefix}-${r}", "-", "_") }

  # aws:SourceArn shapes, not yet verified against a real AssumeRole call.
  agentcore_source_arn      = "arn:aws:bedrock-agentcore:${var.aws_region}:${var.expected_account_id}:*"
  knowledge_base_source_arn = "arn:aws:bedrock:${var.aws_region}:${var.expected_account_id}:knowledge-base/*"

  agent_runtime_statements = {
    for r, k in local.agent_key : r => [
      {
        Sid      = "PullRuntimeImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = [module.in_agents.strings["ecr_agent_${k}_arn"]]
      },
      {
        # GetAuthorizationToken does not support resource-level permissions; "*" is the only valid Resource.
        Sid      = "EcrLoginToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "ManageRuntimeLogGroups"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DescribeLogStreams"]
        Resource = "${local.logs_arn_prefix}:log-group:/aws/bedrock-agentcore/runtimes/${local.agent_runtime_names[r]}-*"
      },
      {
        Sid      = "WriteRuntimeLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${local.logs_arn_prefix}:log-group:/aws/bedrock-agentcore/runtimes/${local.agent_runtime_names[r]}-*:log-stream:*"
      },
    ]
  }

  agent_runtime_roles = {
    for r, k in local.agent_key : "agent_${k}_execution" => {
      name     = "${local.name_prefix}-agent-${r}"
      trust    = { service_principals = ["bedrock-agentcore.amazonaws.com"], source_account = var.expected_account_id, source_arn = local.agentcore_source_arn }
      policies = { pull-and-log = jsonencode({ Version = "2012-10-17", Statement = local.agent_runtime_statements[r] }) }
    }
  }

  # Trust only; whether they exist is this stack's decision (agent checks it), and iam-app attaches the permissions.
  agent_service_role_settings = {
    knowledge_base = {
      key   = "bedrock_kb"
      name  = "${local.name_prefix}-bedrock-kb"
      trust = { service_principals = ["bedrock.amazonaws.com"], source_account = var.expected_account_id, source_arn = local.knowledge_base_source_arn }
    }
    gateway = {
      key   = "agentcore_gateway"
      name  = "${local.name_prefix}-agentcore-gateway"
      trust = { service_principals = ["bedrock-agentcore.amazonaws.com"], source_account = var.expected_account_id, source_arn = local.agentcore_source_arn }
    }
  }

  agent_service_roles = {
    for r in var.agent_service_roles : local.agent_service_role_settings[r].key => {
      name     = local.agent_service_role_settings[r].name
      trust    = local.agent_service_role_settings[r].trust
      policies = {}
    }
  }
}

module "agent_runtime_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.1.0"
  for_each = local.agent_runtime_roles

  name            = each.value.name
  trust           = each.value.trust
  inline_policies = each.value.policies
}

module "agent_service_role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/iam-role/aws"
  version  = "~> 0.1.0"
  for_each = local.agent_service_roles

  name            = each.value.name
  trust           = each.value.trust
  inline_policies = each.value.policies
}
