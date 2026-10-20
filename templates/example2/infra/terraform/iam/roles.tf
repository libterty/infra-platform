locals {
  is_dev = var.env == "dev"

  roles = merge(
    {
      ecs_execution = {
        name  = "${local.name_prefix}-ecs-execution"
        trust = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      api_task = {
        name  = "${local.name_prefix}-api-task"
        trust = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      worker_task = {
        name  = "${local.name_prefix}-worker-task"
        trust = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      lambda = {
        name  = "${local.name_prefix}-lambda"
        trust = { service_principals = ["lambda.amazonaws.com"], source_account = local.account_id, source_arn = null }
      }
      agent_runtime = {
        name  = "${local.name_prefix}-agent-runtime"
        trust = { service_principals = ["bedrock-agentcore.amazonaws.com"], source_account = local.account_id, source_arn = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:*" }
      }
    },
    local.is_dev ? {
      eval_batch = {
        name  = "${local.name_prefix}-eval-batch"
        trust = { service_principals = ["bedrock.amazonaws.com"], source_account = local.account_id, source_arn = "arn:aws:bedrock:${local.region}:${local.account_id}:model-invocation-job/*" }
      }
    } : {},
  )
}

module "role" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/iam-role/aws"
  version = "~> 0.2.0"

  for_each = local.roles

  name  = each.value.name
  trust = each.value.trust
  inline_policies = {
    permissions = jsonencode({ Version = "2012-10-17", Statement = local.statements[each.key] })
  }
}
