locals {
  # containerimage is applied before foundation, so the shared CMK does not exist yet: images use AES256.
  api_repository = {
    name            = "${local.name_prefix}-api"
    lifecycle_rules = var.lifecycle_rules
  }
}

module "api_repository" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ecr-repository/aws"
  version = "~> 0.1.1"

  name            = local.api_repository.name
  lifecycle_rules = local.api_repository.lifecycle_rules
}
