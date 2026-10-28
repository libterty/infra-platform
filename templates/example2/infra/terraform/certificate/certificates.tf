locals {
  zone_id   = module.in.strings["zone_id"]
  zone_name = module.in.strings["zone_name"]

  # Viewers use api; CloudFront reaches the ALB through origin-api. CloudFront forwards the viewer Host header, so the
  # ALB certificate must also cover api.
  alb_certificate = {
    domain_name               = "api.${local.zone_name}"
    subject_alternative_names = ["origin-api.${local.zone_name}"]
  }

  # CloudFront only accepts certificates from us-east-1.
  cloudfront_certificate = {
    domain_name = "api.${local.zone_name}"
    region      = "us-east-1"
  }
}

module "alb_certificate" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/acm-certificate/aws"
  version = "~> 0.1.0"

  domain_name               = local.alb_certificate.domain_name
  subject_alternative_names = local.alb_certificate.subject_alternative_names
  zone_id                   = local.zone_id
}

module "cloudfront_certificate" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/acm-certificate/aws"
  version = "~> 0.1.0"

  domain_name = local.cloudfront_certificate.domain_name
  region      = local.cloudfront_certificate.region
  zone_id     = local.zone_id
}
