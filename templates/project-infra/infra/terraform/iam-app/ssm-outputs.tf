locals {
  # SSM keys cannot contain hyphens: service order-api publishes role_order_api_task_arn.
  service_key = { for s in local.services : s => replace(s, "-", "_") }

  published_strings = merge(
    { for s, k in local.service_key : "role_${k}_task_arn" => module.task_role[s].arn },
    # application reads this flag instead of having its own ECS Exec variable, so the permission and the switch cannot disagree.
    { for s, k in local.service_key : "ecs_exec_${k}" => jsonencode({ enabled = contains(local.ecs_exec_enabled, s) }) },
    # application mounts the collector sidecar for these services. SSM rejects an empty list, so this is JSON in a String; it is "[]" when nothing is traced.
    { tracing = jsonencode(sort(tolist(local.tracing_enabled))) },
    # application injects the ids for these services; "{}" when no service calls AgentCore or Bedrock.
    { agent_access = jsonencode(var.agent_access) },
  )
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-app"
  strings    = local.published_strings
}
