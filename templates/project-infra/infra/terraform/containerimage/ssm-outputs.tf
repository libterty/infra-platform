locals {
  # SSM keys cannot contain hyphens: service order-api publishes ecr_order_api_url.
  service_key = { for s in var.services : s => replace(s, "-", "_") }
  mirror_key  = { for m in var.mirrored_images : m => replace(m, "-", "_") }
  agent_key   = { for r in var.agent_runtimes : r => replace(r, "-", "_") }

  published_strings = merge(
    { for s, k in local.service_key : "ecr_${k}_url" => module.ecr[s].repository_url },
    { for s, k in local.service_key : "ecr_${k}_arn" => module.ecr[s].arn },
    { for m, k in local.mirror_key : "ecr_mirror_${k}_url" => module.ecr_mirror[m].repository_url },
    { for m, k in local.mirror_key : "ecr_mirror_${k}_arn" => module.ecr_mirror[m].arn },
    { for r, k in local.agent_key : "ecr_agent_${k}_url" => module.ecr_agent[r].repository_url },
    { for r, k in local.agent_key : "ecr_agent_${k}_arn" => module.ecr_agent[r].arn },
    # SSM rejects an empty list, so these lists are JSON in a String; each is "[]" when empty.
    { mirrored_images = jsonencode(sort(tolist(var.mirrored_images))) },
    { agent_runtimes = jsonencode(sort(tolist(var.agent_runtimes))) },
  )
  published_lists = {
    services = var.services
  }
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "containerimage"
  strings    = local.published_strings
  lists      = local.published_lists
}
