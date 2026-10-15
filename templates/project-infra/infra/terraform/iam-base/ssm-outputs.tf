locals {
  published_strings = { for k, m in module.role : "role_${k}_arn" => m.arn }
}

module "ssm_publish" {
  source = "../../../../../modules/ssm-publish"

  ssm_prefix = local.ssm_prefix
  stack      = "iam-base"
  strings    = local.published_strings
}
