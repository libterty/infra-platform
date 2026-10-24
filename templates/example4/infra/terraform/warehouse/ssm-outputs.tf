locals {
  # The same five keys in both modes; bi reads host, port and database and never branches on the mode.
  published_strings = {
    redshift_mode             = local.warehouse.mode
    redshift_host             = local.warehouse.host
    redshift_port             = tostring(local.warehouse.port)
    redshift_database         = local.warehouse.database
    redshift_admin_secret_arn = local.warehouse.admin_secret_arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.1"

  ssm_prefix = local.ssm_prefix
  stack      = "warehouse"
  strings    = local.published_strings
}
