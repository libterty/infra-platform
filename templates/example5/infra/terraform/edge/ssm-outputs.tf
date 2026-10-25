locals {
  published_strings = {
    kvs_stream_arns = length(var.cameras) == 0 ? jsonencode({}) : jsonencode({
      for id, c in var.cameras : id => module.kvs[0].stream_arns["${local.name_prefix}-cam-${id}"]
    })
  }
  published_lists = {
    deployment_ids = concat([for k in sort(keys(module.deployment)) : module.deployment[k].deployment_id], [for t in sort(keys(module.camera_deployment)) : module.camera_deployment[t].deployment_id])
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "edge"
  strings    = local.published_strings
  lists      = local.published_lists
}
