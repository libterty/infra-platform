locals {
  # SSM keys cannot contain hyphens: service order-api publishes ecr_order_api_url.
  service_key = { for s in var.services : s => replace(s, "-", "_") }

  published_strings = merge(
    { for s, k in local.service_key : "ecr_${k}_url" => module.ecr[s].repository_url },
    { for s, k in local.service_key : "ecr_${k}_arn" => module.ecr[s].arn },
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
