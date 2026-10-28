# The single distribution of the env (design K16): the SPA from S3 by default, /api/* to the HTTP API. The SPA and the
# API share app.<zone>, so the API needs no CORS and no custom domain.
locals {
  app_domain = "app.${module.in.strings["zone_name"]}"

  cdn = {
    name            = "${local.name_prefix}-web"
    aliases         = [local.app_domain]
    certificate_arn = module.in.strings["web_certificate_arn"]
    web_acl_arn     = module.waf.web_acl_arn
    price_class     = "PriceClass_200"
    origins = {
      site = { type = "s3", domain_name = module.site_bucket.bucket_regional_domain_name }
      api  = { type = "custom", domain_name = module.in.strings["api_endpoint"] }
    }
    default_behavior = { origin = "site" }
    ordered_behaviors = [
      {
        path_pattern    = "/api/*"
        origin          = "api"
        allowed_methods = "all"
        cache_policy    = "Managed-CachingDisabled"
        # The execute-api URL only answers to its own host name, so the viewer's Host must not be forwarded.
        origin_request_policy = "Managed-AllViewerExceptHostHeader"
      },
    ]
    # The API Lambda rejects requests without this header (design K17), so direct calls to execute-api skip nothing.
    origin_verify       = { origin = "api", header_name = var.origin_verify_header_name }
    default_root_object = "index.html"
    spa_fallback        = true
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
  ordered_behaviors          = local.cdn.ordered_behaviors
  origin_verify              = local.cdn.origin_verify
  origin_verify_header_value = var.origin_verify_header_value
  default_root_object        = local.cdn.default_root_object
  spa_fallback               = local.cdn.spa_fallback
}

# The distribution has IPv6 on, so app.<zone> gets both alias records.
locals {
  app_records = {
    for type in ["A", "AAAA"] : lower(type) => {
      name  = local.app_domain
      type  = type
      alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id }
    }
  }
}

module "app_records" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/route53-record/aws"
  version = "~> 0.1.0"

  zone_id = module.in.strings["zone_id"]
  records = local.app_records
}
