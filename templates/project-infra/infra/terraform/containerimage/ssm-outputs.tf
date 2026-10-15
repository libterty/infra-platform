locals {
  # SSM keys cannot contain hyphens: service order-api publishes ecr_order_api_url.
  service_key = { for s in var.services : s => replace(s, "-", "_") }
  mirror_key  = { for m in var.mirrored_images : m => replace(m, "-", "_") }

  published_strings = merge(
    { for s, k in local.service_key : "ecr_${k}_url" => module.ecr[s].repository_url },
    { for s, k in local.service_key : "ecr_${k}_arn" => module.ecr[s].arn },
    { for m, k in local.mirror_key : "ecr_mirror_${k}_url" => module.ecr_mirror[m].repository_url },
    { for m, k in local.mirror_key : "ecr_mirror_${k}_arn" => module.ecr_mirror[m].arn },
    # SSM rejects an empty list, so the mirror list is JSON in a String; it is "[]" when there are no mirrors.
    { mirrored_images = jsonencode(sort(tolist(var.mirrored_images))) },
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
