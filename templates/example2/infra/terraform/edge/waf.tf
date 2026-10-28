# A second WAF on CloudFront (design K9): only here is the client IP the real one, so this rate limit counts clients.
# The ALB WAF stays as it is; behind CloudFront its rate limit counts CloudFront edge addresses.
locals {
  waf = {
    name  = "${local.name_prefix}-api-edge"
    scope = "CLOUDFRONT"
    # Same groups and body size exemption as the ALB WAF, so the edge does not block what the ALB allows.
    managed_rule_groups = [
      { name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] },
      { name = "AWSManagedRulesKnownBadInputsRuleSet", count_overrides = [] },
    ]
    body_size_exempt_path_prefixes = var.body_size_exempt_path_prefixes
    rate_limit = {
      limit           = var.rate_limit_per_5min
      allowlist_cidrs = var.rate_limit_allowlist_cidrs
    }
    # The module adds authorization and cookie; the origin verify header is redacted in case a client sends one.
    logging = {
      retention_days   = var.waf_log_retention_days
      redacted_headers = [lower(var.origin_verify_header_name)]
    }
  }
}

module "waf" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/waf-web-acl/aws"
  version = "~> 0.2.0"

  name                           = local.waf.name
  scope                          = local.waf.scope
  managed_rule_groups            = local.waf.managed_rule_groups
  body_size_exempt_path_prefixes = local.waf.body_size_exempt_path_prefixes
  rate_limit                     = local.waf.rate_limit
  logging                        = local.waf.logging
}
