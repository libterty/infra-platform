locals {
  services = module.in.lists["services"]

  # {"db":["api","worker"]}: only these services may read the database secret.
  data_access      = jsondecode(module.in.strings["data_access"])
  secret_readers   = toset(try(local.data_access["db"], []))
  ecs_exec_enabled = toset(var.ecs_exec_services)

  # The database secret statements (proxy-policy.tf) are also what the task roles of data_access services get: the
  # secret is read by the task role, not injected through the shared execution role (design section 8.2).

  ecs_exec_statements = [
    {
      # The ssmmessages actions do not support resource-level permissions; "*" is the only valid Resource.
      Sid      = "EcsExecChannels"
      Effect   = "Allow"
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Resource = "*"
    },
  ]

  task_policies = {
    for s in local.services : s => merge(
      local.database.enabled && contains(local.secret_readers, s) ? {
        read-db-secret = jsonencode({ Version = "2012-10-17", Statement = local.db_secret_statements })
      } : {},
      contains(local.ecs_exec_enabled, s) ? {
        ecs-exec = jsonencode({ Version = "2012-10-17", Statement = local.ecs_exec_statements })
      } : {},
    )
  }
}

locals {
  task_trust = { service_principals = ["ecs-tasks.amazonaws.com"], source_account = var.expected_account_id }
}

module "task_role" {
  source   = "../../../../../modules/iam-role"
  for_each = toset(local.services)

  name            = "${local.name_prefix}-${each.key}-task"
  trust           = local.task_trust
  inline_policies = local.task_policies[each.key]
}
