locals {
  published_strings = {
    alb_certificate_arn        = module.alb_certificate.certificate_arn
    cloudfront_certificate_arn = module.cloudfront_certificate.certificate_arn
  }
}

module "ssm_publish" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-publish/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  stack      = "certificate"
  strings    = local.published_strings
}
