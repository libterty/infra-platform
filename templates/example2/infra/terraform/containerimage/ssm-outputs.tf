locals {
  published_strings = {
    # SSM rejects an empty list and a map, so these are JSON in a String; the Runtime list is "[]" when empty.
    agent_runtimes      = jsonencode(sort(tolist(var.agent_runtimes)))
    ecr_repository_urls = jsonencode({ for key, repo in local.repository : key => repo.url })
    ecr_repository_arns = jsonencode({ for key, repo in local.repository : key => repo.arn })
  }

  published_lists = {
    services = var.services
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "containerimage"
  strings    = local.published_strings
  lists      = local.published_lists
}
