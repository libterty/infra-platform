locals {
  # Services and Runtimes share one key space (checked in variables.tf). The name has no env in it on purpose: two envs
  # in one account must be able to share a repository, one creating it and the other adopting it (adopt_existing).
  repository_names = merge(
    { for s in var.services : s => "${var.project}-${s}" },
    { for r in var.agent_runtimes : r => "${var.project}-${r}" },
  )

  repositories = {
    for key, name in local.repository_names : key => {
      name            = name
      lifecycle_rules = var.lifecycle_rules
    }
  }
}

module "ecr" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecr-repository/aws"
  version = "~> 0.1.0"

  for_each = var.adopt_existing ? {} : local.repositories

  name            = each.value.name
  lifecycle_rules = each.value.lifecycle_rules
}

data "aws_ecr_repository" "existing" {
  for_each = var.adopt_existing ? local.repositories : {}

  name = each.value.name
}

locals {
  repository = var.adopt_existing ? {
    for key, repo in data.aws_ecr_repository.existing : key => { url = repo.repository_url, arn = repo.arn, name = repo.name }
    } : {
    for key, repo in module.ecr : key => { url = repo.repository_url, arn = repo.arn, name = repo.name }
  }
}
