# One certificate for the single CloudFront distribution of the web stack (design K16): the SPA and /api/* share
# app.<zone>, so there is no regional certificate. CloudFront only accepts certificates in us-east-1.
locals {
  web_certificate = {
    domain_name = "app.${module.in.strings["zone_name"]}"
    zone_id     = module.in.strings["zone_id"]
    region      = "us-east-1"
    # acm-certificate adds no Name tag because wildcard names are not valid tag values; this name has no wildcard.
    tags = { Name = "${local.name_prefix}-web" }
  }
}

module "web_certificate" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/acm-certificate/aws"
  version = "~> 0.1.0"

  domain_name = local.web_certificate.domain_name
  zone_id     = local.web_certificate.zone_id
  region      = local.web_certificate.region
  tags        = local.web_certificate.tags
}
