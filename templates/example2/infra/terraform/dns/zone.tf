module "zone" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/route53-zone/aws"
  version = "~> 0.1.0"

  name    = var.zone_name
  comment = "${local.name_prefix} public zone"
}
