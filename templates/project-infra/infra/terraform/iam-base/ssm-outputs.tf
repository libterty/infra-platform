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
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-base"
  strings    = local.published_strings
}
