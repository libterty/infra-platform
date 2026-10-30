# The SPA on the CloudFront default domain (design 7): no aliases, so no certificate. The web-invalidate role may only
# invalidate a distribution carrying the tags in iam/naming.tf; the provider's default_tags (providers.tf) put them on.
locals {
  cdn = {
    name        = "${local.name_prefix}-web"
    price_class = "PriceClass_200"
    origins = {
      site = { type = "s3", domain_name = module.site_bucket.bucket_regional_domain_name }
    }
    default_behavior    = { origin = "site" }
    default_root_object = "index.html"
    spa_fallback        = true
  }
}

module "cdn" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/cloudfront-distribution/aws"
  version = "~> 0.1.0"

  name                = local.cdn.name
  price_class         = local.cdn.price_class
  origins             = local.cdn.origins
  default_behavior    = local.cdn.default_behavior
  default_root_object = local.cdn.default_root_object
  spa_fallback        = local.cdn.spa_fallback
}
