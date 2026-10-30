# Created PENDING: someone must authorize it once in the console (GitHub App install) before a pipeline can use it.
locals {
  connection = {
    name          = "${local.name_prefix}-github"
    provider_type = "GitHub"
  }
}

module "connection" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/codeconnections-connection/aws"
  version = "~> 0.1.0"

  name          = local.connection.name
  provider_type = local.connection.provider_type
}
