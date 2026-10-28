# Always on (design K14): the WAF on CloudFront is the only one in front of the API, because an HTTP API cannot have
# its own (design 4.3).
locals {
  waf = {
    name  = "${local.name_prefix}-web"
    scope = "CLOUDFRONT"
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet" },
      { name = "AWSManagedRulesKnownBadInputsRuleSet" },
    ]
    rate_limit = { limit = var.waf_rate_limit_per_5min }
    # The module adds authorization and cookie; the origin verify header is redacted too in case a client sends one.
    logging = {
      retention_days   = var.log_retention_days
      redacted_headers = [lower(var.origin_verify_header_name)]
    }
  }
}

module "waf" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/waf-web-acl/aws"
  version = "~> 0.2.0"

  name                = local.waf.name
  scope               = local.waf.scope
  managed_rule_groups = local.waf.managed_rule_groups
  rate_limit          = local.waf.rate_limit
  logging             = local.waf.logging
}
