locals {
  # containerimage is applied before foundation, so the shared CMK does not exist yet: images use AES256.
  # The keys are the components; iam builds the repository ARNs from the URLs published here.
  repositories = {
    api = { name = "${local.name_prefix}-api", lifecycle_rules = var.lifecycle_rules }
    fn  = { name = "${local.name_prefix}-fn", lifecycle_rules = var.lifecycle_rules }
  }
}

module "repository" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source   = "app.terraform.io/libterty/ecr-repository/aws"
  version  = "~> 0.1.1"
  for_each = local.repositories

  name            = each.value.name
  lifecycle_rules = each.value.lifecycle_rules
}
