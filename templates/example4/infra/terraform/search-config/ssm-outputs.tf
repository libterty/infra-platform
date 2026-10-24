locals {
  # The FGAC role name is the key of writer_roles; the pipeline stack and people refer to it by that name.
  published_strings = {
    firehose_writer_role = one(module.config.writer_role_names)
  }
  published_lists = {
    ism_policy_ids = module.config.ism_policy_ids
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "search-config"
  strings    = local.published_strings
  lists      = local.published_lists
}
