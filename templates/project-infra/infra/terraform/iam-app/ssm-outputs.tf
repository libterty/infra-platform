locals {
  # SSM keys cannot contain hyphens: service order-api publishes role_order_api_task_arn.
  service_key = { for s in local.services : s => replace(s, "-", "_") }

  published_strings = merge(
    { for s, k in local.service_key : "role_${k}_task_arn" => module.task_role[s].arn },
    # application reads this flag instead of having its own ECS Exec variable, so the permission and the switch cannot disagree.
    { for s, k in local.service_key : "ecs_exec_${k}" => jsonencode({ enabled = contains(local.ecs_exec_enabled, s) }) },
  )
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-app"
  strings    = local.published_strings
}
