# CloudFront in front of the public ALB (design D3, K7, K8). Clients use api.<zone>; CloudFront reaches the ALB as
# origin-api.<zone> over HTTPS only and adds the origin verify header the ALB listener rules require.
locals {
  api_domain    = "api.${module.shared.strings["zone_name"]}"
  origin_domain = "origin-api.${module.shared.strings["zone_name"]}"

  cdn = {
    name            = "${local.name_prefix}-api"
    aliases         = [local.api_domain]
    certificate_arn = module.shared.strings["cloudfront_certificate_arn"]
    web_acl_arn     = module.waf.web_acl_arn
    price_class     = "PriceClass_200"
    # The module fixes custom origins to https-only and TLSv1.2.
    origins = {
      alb = {
        type        = "custom"
        domain_name = local.origin_domain
        custom      = { read_timeout = var.origin_read_timeout }
      }
    }
    default_behavior = {
      origin          = "alb"
      allowed_methods = "all"
      cache_policy    = "Managed-CachingDisabled"
      # AllViewer forwards the viewer Host (api.<zone>): the ALB rules match on it, and CloudFront then checks the ALB
      # certificate against it, which is why that certificate also covers api.<zone> (design K8).
      origin_request_policy = "Managed-AllViewer"
    }
    origin_verify = { origin = "alb", header_name = var.origin_verify_header_name }
  }
}

module "cdn" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/cloudfront-distribution/aws"
  version = "~> 0.1.0"

  name                       = local.cdn.name
  aliases                    = local.cdn.aliases
  certificate_arn            = local.cdn.certificate_arn
  web_acl_arn                = local.cdn.web_acl_arn
  price_class                = local.cdn.price_class
  origins                    = local.cdn.origins
  default_behavior           = local.cdn.default_behavior
  origin_verify              = local.cdn.origin_verify
  origin_verify_header_value = var.origin_verify_header_value
}
