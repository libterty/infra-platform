locals {
  waf_kill_switch = {
    action = var.waf_kill_switch_mode
    # Only a blocking kill switch may carry a body.
    response_json = var.waf_kill_switch_mode == "block" ? jsonencode({ status = "error", code = "SERVICE_PAUSED" }) : null
  }

  waf_rate_limit = {
    limit           = var.rate_limit_per_5min
    allowlist_cidrs = var.rate_limit_allowlist_cidrs
  }

  # The common rule set only counts oversized bodies; the module adds a rule that blocks them outside the exempt paths.
  waf_managed_rule_groups = [
    { name = "AWSManagedRulesCommonRuleSet", count_overrides = ["SizeRestrictions_BODY"] },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", count_overrides = [] },
  ]

  # The secret travels in this header, so it must never reach the WAF log. The module lowercases and adds
  # authorization and cookie on its own.
  waf_logging = {
    retention_days   = var.waf_log_retention_days
    redacted_headers = [lower(var.origin_verify_header_name)]
  }
}

module "waf" {
  # HCP private registry (ADR-0004); another org or no HCP token: see docs/guides/consuming-modules.md
  source  = "app.terraform.io/libterty/waf-web-acl/aws"
  version = "~> 0.1.0"

  name                           = local.alb_name
  kill_switch                    = local.waf_kill_switch
  rate_limit                     = local.waf_rate_limit
  managed_rule_groups            = local.waf_managed_rule_groups
  body_size_exempt_path_prefixes = var.body_size_exempt_path_prefixes
  logging                        = local.waf_logging
}
