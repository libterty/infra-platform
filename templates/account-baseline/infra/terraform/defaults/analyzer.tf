# External access analysis of this account only; it is free. Unused access analysis is billed per role and user, so
# it stays off (design K9).
locals {
  analyzer = {
    name = "${local.name_prefix}-account"
    type = "ACCOUNT"
  }
}

module "access_analyzer" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/access-analyzer/aws"
  version = "~> 0.1.0"

  name = local.analyzer.name
  type = local.analyzer.type
}
