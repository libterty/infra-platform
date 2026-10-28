locals {
  # The ALB this stack fronts; loadbalancer is a late stack, so its tree A keys may be read here.
  ssm_input_strings = {
    alb_dns_name = "loadbalancer/alb_dns_name"
    alb_zone_id  = "loadbalancer/alb_zone_id"
  }

  shared_input_strings = {
    zone_id   = "infra/zone_id"
    zone_name = "infra/zone_name"
    # us-east-1 certificate for api.<zone>, issued by the certificate stack.
    cloudfront_certificate_arn = "infra/cloudfront_certificate_arn"
  }
}

module "in" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.ssm_prefix
  strings    = local.ssm_input_strings
}

module "shared" {
  # Tree B: published by the bridge stack, or by someone else for envs listed in EXTERNAL_SHARED_ENVS (stacks.sh).
  source  = "app.terraform.io/libterty/ssm-read/aws"
  version = "~> 0.1.0"

  ssm_prefix = local.shared_ssm_prefix
  strings    = local.shared_input_strings
}
