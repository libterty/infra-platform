locals {
  published_strings = merge(
    { for k, m in module.role : "role_${k}_arn" => m.arn },
    { for k, m in module.agent_runtime_role : "role_${k}_arn" => m.arn },
    { for k, m in module.agent_service_role : "role_${k}_arn" => m.arn },
    # agent checks it before using a service role. SSM rejects an empty list, so this is JSON in a String; it is "[]" when empty.
    { agent_service_roles = jsonencode(sort(tolist(var.agent_service_roles))) },
  )
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-base"
  strings    = local.published_strings
}
